require 'finita/common'
require 'finita/orderer'


module Finita::Evaluator


class EvaluatorCode < Finita::CodeTemplate

  attr_reader :gtor, :evaluator, :name, :type, :system, :code

  def initialize(gtor, evaluator, system)
    @gtor = gtor
    @evaluator = evaluator
    @system = system
    @name = system.name
    @type = Finita::Generator::Scalar[system.type]
  end

  def write_intf(stream)
    stream << "void #{name}EvaluatorSetup();"
    system.linear? ? write_intf_linear(stream) : write_intf_nonlinear(stream)
  end

  def write_intf_linear(stream)
    stream << %$
      #{type} #{name}EvaluateLHS(int, int);
      #{type} #{name}EvaluateRHS(int);
    $
  end

  def write_intf_nonlinear(stream)
    stream << %$
      #{type} #{name}EvaluateJacobian(int, int);
      #{type} #{name}EvaluateResidual(int);
    $
  end

  def write_defs(stream)
    system.linear? ? write_defs_linear(stream) : write_defs_nonlinear(stream)
  end

end # EvaluatorCode


class Numeric

  class Code < EvaluatorCode

    def entities; super + [Finita::Orderer::StaticCode.instance, Finita::FpMatrixCode.instance, Finita::FpVectorCode.instance] + code.values end

    def initialize(gtor, evaluator, system)
      super
      @code = {}
      system.equations.each do |eqn|
        eqn.bind(gtor)
        eqn.lhs.each do |k,v|
          code[v] = gtor << FpCode.new(v, eqn.type)
        end
        code[eqn.rhs] = gtor << FpCode.new(eqn.rhs, eqn.type)
      end
    end

    def write_defs(stream)
      stream << %$
        typedef #{type} (*#{name}Fp)(int, int, int);
        extern FinitaOrderer #{name}Orderer;
        static FinitaFpMatrix #{name}FpMatrix;
        static FinitaFpVector #{name}FpVector;
      $
      stream << %$
        void #{name}EvaluatorSetup() {
          int index, size;
          FINITA_ASSERT(#{name}Orderer.frozen);
          size = FinitaOrdererSize(&#{name}Orderer);
          FinitaFpMatrixCtor(&#{name}FpMatrix, pow(size, 1.1)); /* TODO more accurate storage size calculation */
          FinitaFpVectorCtor(&#{name}FpVector, &#{name}Orderer);
          for(index = 0; index < size; ++index) {
            int x, y, z;
            FinitaNode row = FinitaOrdererNode(&#{name}Orderer, index);
            x = row.x; y = row.y; z = row.z;
      $
      system.equations.each do |eqn|
        stream << "if(row.field == #{system.unknowns.index(eqn.unknown)} && #{gtor[eqn.domain].within_xyz}) {"
        stream << "FinitaFpVectorMerge(&#{name}FpVector, index, (FinitaFp)#{code[eqn.rhs].name});"
        eqn.lhs.each do |ref,fp|
          # TODO make sure ref.arg is of type Field
          stream << %$
            FinitaFpMatrixMerge(&#{name}FpMatrix, index, FinitaOrdererIndex(&#{name}Orderer, FinitaNodeNew(#{system.unknowns.index(ref.arg)}, #{ref.xindex}, #{ref.yindex}, #{ref.zindex})), (FinitaFp)#{code[fp].name});
          $
        end
        stream << (eqn.through? ? '}' : 'break;}')
      end
      stream << '}}'
      super
    end

    def write_defs_linear(stream)
      stream << %$
        #{type} #{name}EvaluateLHS(int row, int column) {
          #{type} result = 0;
          FinitaNode node;
          FinitaFpListIt it;
          value = #{name}GetIndex(column);
          FinitaFpListItCtor(&it, FinitaFpMatrixAt(&#{name}FpMatrix, row, column));
          while(FinitaFpListItHasNext(&it)) {
            result += ((#{name}fp)FinitaFpListItNext(&it))(node.x, node.y, node.z);
          }
          return result;
        }
        #{type} #{name}EvaluateRHS(int index) {
          FinitaNode node;
          FinitaFpListIt it;
          #{type} result = 0;
          node = FinitaOrdererNode(&#{name}Orderer, index);
          FinitaFpListItCtor(&it, FinitaFpVectorAt(&#{name}FpVector, index));
          while(FinitaFpListItHasNext(&it)) {
            result += ((#{name}Fp)FinitaFpListItNext(&it))(node.x, node.y, node.z);
          }
          return result;
        }
      $
    end

    def write_defs_nonlinear(stream)
      stream << %$
        #{type} #{name}EvaluateJacobian(int row, int column) {
          #{type} value, eta, result = 0, eps = 100*#{evaluator.relative_tolerance};
          FinitaNode node;
          FinitaFpListIt it;
          value = #{name}GetIndex(column);
          eta = fabs(value) > eps ? value*#{evaluator.relative_tolerance} : (value < 0 ? -1 : 1)*eps; /* From PETSc's MatFD implementation '*/
          node = FinitaOrdererNode(&#{name}Orderer, row);
          FinitaFpListItCtor(&it, FinitaFpMatrixAt(&#{name}FpMatrix, row, column));
          while(FinitaFpListItHasNext(&it)) {
            #{name}Fp fp = (#{name}Fp)FinitaFpListItNext(&it);
            #{name}SetIndex(column, value + eta);
            result += fp(node.x, node.y, node.z);
            #{name}SetIndex(column, value - eta);
            result -= fp(node.x, node.y, node.z);
          }
          #{name}SetIndex(column, value);
          return result/(2*eta);
        }
        #{type} #{name}EvaluateResidual(int index) {
          #{type} result = 0;
          FinitaNode node;
          FinitaFpListIt it;
          node = FinitaOrdererNode(&#{name}Orderer, index);
          FinitaFpListItCtor(&it, FinitaFpVectorAt(&#{name}FpVector, index));
          while(FinitaFpListItHasNext(&it)) {
            result += ((#{name}Fp)FinitaFpListItNext(&it))(node.x, node.y, node.z);
          }
          return result;
        }
      $
    end

  end # Code

  attr_reader :relative_tolerance

  def initialize(rtol)
    @relative_tolerance = rtol
  end

  def bind(gtor, system)
    gtor << Code.new(gtor, self, system)
  end

end # Numeric


end # Finita::Evaluator
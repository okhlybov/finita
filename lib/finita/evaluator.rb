require 'finita/common'
require 'finita/orderer'


module Finita::Evaluator


class StaticCode < Finita::StaticCodeTemplate

  def write_intf(stream)
    stream << %$
      typedef struct  {
        int row, column;
      } FinitaRowColumn;
    $
  end

end # StaticCode


class EvaluatorCode < Finita::CodeTemplate

  attr_reader :gtor, :evaluator, :name, :type, :system, :code

  def entities; super + [StaticCode.instance] end

  def initialize(evaluator, gtor, system)
    @gtor = gtor
    @evaluator = evaluator
    @system = system
    @name = system.name
    @type = Finita::Generator::Scalar[system.type]
    gtor << self
  end

  def write_intf(stream)
    stream << %$
      void #{name}SetupEvaluator();
      void #{name}EvaluatorRowColumn(FinitaRowColumn**, size_t*);
  $
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
    stream << %$
      typedef #{type} (*#{name}Fp)(int, int, int);
      extern FinitaOrderer #{name}Orderer;
      static FinitaFpMatrix #{name}FpMatrix;
      static FinitaFpVector #{name}FpVector;
      void #{name}EvaluatorRowColumn(FinitaRowColumn** rc, size_t* size) {
        int index = 0;
        FinitaFpMatrixIt it;
        *size = FinitaFpMatrixSize(&#{name}FpMatrix);
        *rc = (FinitaRowColumn*)FINITA_MALLOC(*size*sizeof(FinitaRowColumn)); FINITA_ASSERT(*rc);
        FinitaFpMatrixItCtor(&it, &#{name}FpMatrix);
        while(FinitaFpMatrixItHasNext(&it)) {
          FinitaFpMatrixKey key = FinitaFpMatrixItNextKey(&it);
          (*rc)[index].row = key.row_index;
          (*rc)[index].column = key.column_index;
          ++index;
        }
      }
    $
    system.linear? ? write_defs_linear(stream) : write_defs_nonlinear(stream)
  end

end # EvaluatorCode


class Numeric

  class Code < EvaluatorCode

    def entities; super + [Finita::Orderer::StaticCode.instance, Finita::FpMatrixCode.instance, Finita::FpVectorCode.instance] + code.values end

    def initialize(evaluator, gtor, system)
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
      super
      stream << %$
        void #{name}SetupEvaluator() {
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
    end

    def write_defs_linear(stream)
      stream << %$
        #{type} #{name}EvaluateLHS(int row, int column) {
          #{type} result = 0;
          FinitaNode node;
          FinitaFpListIt it;
          node = FinitaOrdererNode(&#{name}Orderer, row);
          FinitaFpListItCtor(&it, FinitaFpMatrixAt(&#{name}FpMatrix, row, column));
          while(FinitaFpListItHasNext(&it)) {
            result += ((#{name}Fp)FinitaFpListItNext(&it))(node.x, node.y, node.z);
          }
          return result;
        }
        #{type} #{name}EvaluateRHS(int index) {
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

    def write_defs_nonlinear(stream)
      stream << %$
        #{type} #{name}EvaluateJacobian(int row, int column) {
          #{type} value, eta, result = 0, eps = 100*#{evaluator.relative_tolerance};
          FinitaNode node;
          FinitaFpListIt it;
          value = #{name}GetIndex(column);
          node = FinitaOrdererNode(&#{name}Orderer, row);
          eta = fabs(value) > eps ? value*#{evaluator.relative_tolerance} : (value < 0 ? -1 : 1)*eps; /* From the PETSc's MatFD implementation '*/
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
    Code.new(self, gtor, system)
  end

end # Numeric


end # Finita::Evaluator
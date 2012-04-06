require 'finita/common'


module Finita


class MatrixEvaluatorCode < Finita::StaticCodeTemplate
  attr_reader :type, :scalar_type, :func_list_code
  def entities; super + [Finita::NodeCode.instance, func_list_code] end
  def initialize(type, scalar)
    @type = type
    @func_list_code = Finita::FuncList::Code[scalar]
    @scalar_type = Finita::Generator::Scalar[scalar]
  end
  def write_intf(stream)
    stream << %$
    typedef #{scalar_type} (*#{type}Func)(#{func_list_code.type}*, FinitaNode, FinitaNode);
    typedef struct {
      FinitaNode row, column;
      #{func_list_code.type}* plist;
      #{type}Func fp;
    } #{type};
  $
  end
end # MatrixEvaluatorCode


class IntegerMatrixEvaluatorCode < MatrixEvaluatorCode
  def initialize
    super('FinitaIntegerMatrixEvaluator', Integer)
  end
end # IntegerMatrixEvaluatorCode


class FloatMatrixEvaluatorCode < MatrixEvaluatorCode
  def initialize
    super('FinitaFloatMatrixEvaluator', Float)
  end
end # FloatMatrixEvaluatorCode


class ComplexMatrixEvaluatorCode < MatrixEvaluatorCode
  def initialize
    super('FinitaComplexMatrixEvaluator', Complex)
  end
end # ComplexMatrixEvaluatorCode


module MatrixEvaluator
  Code = {Integer=>IntegerMatrixEvaluatorCode.instance, Float=>FloatMatrixEvaluatorCode.instance, Complex=>ComplexMatrixEvaluatorCode.instance}
end # MatrixEvaluator


class VectorEvaluatorCode < Finita::StaticCodeTemplate
  attr_reader :type, :scalar_type, :func_list_code
  def entities; super + [Finita::NodeCode.instance, func_list_code] end
  def initialize(type, scalar)
    @type = type
    @func_list_code = Finita::FuncList::Code[scalar]
    @scalar_type = Finita::Generator::Scalar[scalar]
  end
  def write_intf(stream)
    stream << %$
    typedef #{scalar_type} (*#{type}Func)(#{func_list_code.type}*, FinitaNode);
    typedef struct {
      FinitaNode row;
      #{func_list_code.type}* plist;
      #{type}Func fp;
    } #{type};
  $
  end
end # VectorEvaluatorCode


class IntegerVectorEvaluatorCode < VectorEvaluatorCode
  def initialize
    super('FinitaIntegerVectorEvaluator', Integer)
  end
end # IntegerVectorEvaluatorCode


class FloatVectorEvaluatorCode < VectorEvaluatorCode
  def initialize
    super('FinitaFloatVectorEvaluator', Float)
  end
end # FloatVectorEvaluatorCode


class ComplexVectorEvaluatorCode < VectorEvaluatorCode
  def initialize
    super('FinitaComplexVectorEvaluator', Complex)
  end
end # ComplexVectorEvaluatorCode


module VectorEvaluator
  Code = {Integer=>IntegerVectorEvaluatorCode.instance, Float=>FloatVectorEvaluatorCode.instance, Complex=>ComplexVectorEvaluatorCode.instance}
end # VectorEvaluator


end # Finita


module Finita::Evaluator


class EvaluatorCode < Finita::CodeTemplate

  attr_reader :gtor, :evaluator, :name, :scalar_type, :system, :code

  attr_reader :func_list_code, :func_matrix_code, :func_vector_code, :matrix_evaluator_code, :vector_evaluator_code

  def entities; super + [Finita::NodeSetCode.instance, func_matrix_code, func_vector_code, matrix_evaluator_code, vector_evaluator_code] end

  def initialize(evaluator, gtor, system)
    @gtor = gtor
    @evaluator = evaluator
    @system = system
    @name = system.name
    @scalar_type = Finita::Generator::Scalar[system.type]
    @func_list_code = Finita::FuncList::Code[system.type]
    @func_matrix_code = Finita::FuncMatrix::Code[system.type]
    @func_vector_code = Finita::FuncVector::Code[system.type]
    @matrix_evaluator_code = Finita::MatrixEvaluator::Code[system.type]
    @vector_evaluator_code = Finita::VectorEvaluator::Code[system.type]
    gtor << self
  end

  def write_intf(stream)
    stream << %$
      extern #{func_matrix_code.type} #{name}SymbolicMatrix;
      extern #{func_vector_code.type} #{name}SymbolicVector;
      #{scalar_type} #{name}EvaluateVector(FinitaNode);
      #{scalar_type} #{name}EvaluateMatrix(FinitaNode, FinitaNode);
      void #{name}MatrixEvaluatorCtor(#{matrix_evaluator_code.type}*, FinitaNode, FinitaNode);
      void #{name}VectorEvaluatorCtor(#{vector_evaluator_code.type}*, FinitaNode);
      void #{name}SetupEvaluator();
  $
  end

  def write_defs(stream)
    stream << %$
      FinitaNodeSet #{name}Nodes;
      #{func_matrix_code.type} #{name}SymbolicMatrix;
      #{func_vector_code.type} #{name}SymbolicVector;
    $
    system.linear? ? write_defs_linear(stream) : write_defs_nonlinear(stream)
    stream << %$
      void #{name}MatrixEvaluatorCtor(#{matrix_evaluator_code.type}* self, FinitaNode row, FinitaNode column) {
        FINITA_ASSERT(self);
        self->row = row;
        self->column = column;
        self->plist = #{func_matrix_code.at}(&#{name}SymbolicMatrix, row, column);
        self->fp = #{name}MatrixEntryEvaluator;
      }
      void #{name}VectorEvaluatorCtor(#{vector_evaluator_code.type}* self, FinitaNode row) {
        FINITA_ASSERT(self);
        self->row = row;
        self->plist = #{func_vector_code.at}(&#{name}SymbolicVector, row);
        self->fp = #{name}VectorEntryEvaluator;
      }
      #{scalar_type} #{name}EvaluateMatrix(FinitaNode row, FinitaNode column) {
        return #{name}MatrixEntryEvaluator(#{func_matrix_code.at}(&#{name}SymbolicMatrix, row, column), row, column);
      }
      #{scalar_type} #{name}EvaluateVector(FinitaNode row) {
        return #{name}VectorEntryEvaluator(#{func_vector_code.at}(&#{name}SymbolicVector, row), row);
      }
    $
  end

end # EvaluatorCode


class Numeric

  class Code < EvaluatorCode

    def entities; super + code.values end

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
        extern #{scalar_type} #{name}GetNode(FinitaNode);
        extern void #{name}SetNode(#{scalar_type}, FinitaNode);
        void #{name}SetupEvaluator() {
          int size = 0;
          FinitaNodeSet nodes;
          FinitaNodeSetIt it;
      $
      system.unknowns.each do |u|
        stream << "size += #{gtor[u].node_count};"
      end
      stream << "FinitaNodeSetCtor(&nodes, size);"
      system.equations.each do |eqn|
        gtor[eqn.domain].foreach_code(stream) {
          stream << "FinitaNodeSetPut(&nodes, FinitaNodeNew(#{system.unknowns.index(eqn.unknown)}, x, y, z));"
        }
      end
      stream << %$
        size = FinitaNodeSetSize(&nodes);
        #{func_matrix_code.ctor}(&#{name}SymbolicMatrix, pow(size, 1.1));
        #{func_vector_code.ctor}(&#{name}SymbolicVector, size);
        FinitaNodeSetCtor(&#{name}Nodes, size);
        FinitaNodeSetItCtor(&it, &nodes);
        while(FinitaNodeSetItHasNext(&it)) {
          int x, y, z;
          FinitaNode column, row = FinitaNodeSetItNext(&it);
          x = row.x; y = row.y; z = row.z;
      $
      system.equations.each do |eqn|
        stream << "if(row.field == #{system.unknowns.index(eqn.unknown)} && #{gtor[eqn.domain].within_xyz}) {"
        eqn.lhs.each do |ref,fp|
          stream << %$
            column = FinitaNodeNew(#{system.unknowns.index(ref.arg)}, #{ref.xindex}, #{ref.yindex}, #{ref.zindex});
            #{func_matrix_code.merge}(&#{name}SymbolicMatrix, row, column, #{code[fp].name});
            FinitaNodeSetPut(&#{name}Nodes, column);
          $
        end
        stream << %$
          #{func_vector_code.merge}(&#{name}SymbolicVector, row, #{code[eqn.rhs].name});
          FinitaNodeSetPut(&#{name}Nodes, row);
        $
        stream << (eqn.through? ? '}' : 'continue;}')
      end
      stream << '}'
      stream << %$
        FinitaNodeSetItCtor(&it, &#{name}Nodes);
        while(FinitaNodeSetItHasNext(&it)) {
          FinitaMatrixKey key;
          FinitaNode node = FinitaNodeSetItNext(&it);
          key.row = key.column = node;
          if(!#{func_matrix_code.contains_key}(&#{name}SymbolicMatrix, key)) {
            FINITA_ASSERT(!#{func_vector_code.contains_key}(&#{name}SymbolicVector, node));
            #{func_matrix_code.put}(&#{name}SymbolicMatrix, key, NULL);
            #{func_vector_code.put}(&#{name}SymbolicVector, node, NULL);
          }
        }
      $
      stream << '}'
    end

    def write_defs_linear(stream)
      stream << %$
      static #{scalar_type} #{name}MatrixEntryEvaluator(#{func_list_code.type}* fps, FinitaNode row, FinitaNode column) {
          if(fps) {
            #{func_list_code.it} it;
            #{scalar_type} result = 0;
            #{func_list_code.it_ctor}(&it, fps);
            while(#{func_list_code.it_has_next}(&it)) {
              result += #{func_list_code.it_next}(&it)(row.x, row.y, row.z);
            }
            return result;
          } else {
            return 1;
          }
        }
        static #{scalar_type} #{name}VectorEntryEvaluator(#{func_list_code.type}* fps, FinitaNode row) {
          if(fps) {
            #{scalar_type} result = 0;
            #{func_list_code.it} it;
            #{func_list_code.it_ctor}(&it, fps);
            while(#{func_list_code.it_has_next}(&it)) {
              result += #{func_list_code.it_next}(&it)(row.x, row.y, row.z);
            }
            return result;
          } else {
            return #{name}GetNode(row);
          }
        }
      $
    end

    def write_defs_nonlinear(stream)
      stream << %$
        static #{scalar_type} #{name}MatrixEntryEvaluator(#{func_list_code.type}* fps, FinitaNode row, FinitaNode column) {
          if(fps) {
            #{func_list_code.it} it;
            #{scalar_type} value, eta, result = 0, eps = 100*#{evaluator.relative_tolerance};
            value = #{name}GetNode(column);
            eta = fabs(value) > eps ? value*#{evaluator.relative_tolerance} : (value < 0 ? -1 : 1)*eps; /* from the PETSc's MatFD implementation '*/
            #{func_list_code.it_ctor}(&it, fps);
            while(#{func_list_code.it_has_next}(&it)) {
              #{func_list_code.element_type} fp = #{func_list_code.it_next}(&it);
              #{name}SetNode(value + eta, column);
              result += fp(row.x, row.y, row.z);
              #{name}SetNode(value - eta, column);
              result -= fp(row.x, row.y, row.z);
            }
            #{name}SetNode(value, column);
            return result/(2*eta);
          } else {
            return 1;
          }
        }
        static #{scalar_type} #{name}VectorEntryEvaluator(#{func_list_code.type}* fps, FinitaNode row) {
          if(fps) {
            #{func_list_code.it} it;
            #{scalar_type} result = 0;
            #{func_list_code.it_ctor}(&it, fps);
            while(#{func_list_code.it_has_next}(&it)) {
              result += #{func_list_code.it_next}(&it)(row.x, row.y, row.z);
            }
            return result;
          } else {
            return #{name}GetNode(row);
          }
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
require 'finita/common'


module Finita::Evaluator


class StaticCode < Finita::StaticCodeTemplate

  def entities; super + [Finita::FpListCode.instance] end
  def write_intf(stream)
    stream << %$
      typedef struct  {
        FinitaNode row, column;
        FinitaFpList* fps;
      } FinitaEvaluatorEntry;
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
      extern FinitaNodeSet #{name}Nodes;
      extern FinitaMatrix #{name}SymbolicMatrix;
      extern FinitaVector #{name}SymbolicVector;
      extern FinitaEvaluatorEntry* #{name}MatrixEntry;
      extern FinitaEvaluatorEntry* #{name}VectorEntry;
      void #{name}SetupEvaluator1();
      void #{name}SetupEvaluator2();
      #{type} #{name}EvaluateMatrix(FinitaNode, FinitaNode);
      #{type} #{name}EvaluateVector(FinitaNode);
  $
  end

  def write_defs(stream)
    stream << %$
      typedef #{type} (*#{name}Fp)(int, int, int);
      FinitaMatrix #{name}SymbolicMatrix;
      FinitaVector #{name}SymbolicVector;
      FinitaNodeSet #{name}Nodes;
      FinitaEvaluatorEntry* #{name}MatrixEntry;
      FinitaEvaluatorEntry* #{name}VectorEntry;
      #{type} #{name}EvaluateMatrixEntry(FinitaFpList*, FinitaNode, FinitaNode);
      #{type} #{name}EvaluateVectorEntry(FinitaFpList*, FinitaNode);
      #{type} #{name}EvaluateMatrix(FinitaNode row, FinitaNode column) {
        return #{name}EvaluateMatrixEntry(FinitaMatrixAt(&#{name}SymbolicMatrix, row, column), row, column);
      }
      #{type} #{name}EvaluateVector(FinitaNode row) {
        return #{name}EvaluateVectorEntry(FinitaVectorAt(&#{name}SymbolicVector, row), row);
      }
    $
    system.linear? ? write_defs_linear(stream) : write_defs_nonlinear(stream)
  end

end # EvaluatorCode


class Numeric

  class Code < EvaluatorCode

    def entities; super + [Finita::NodeSetCode.instance, Finita::MatrixCode.instance, Finita::VectorCode.instance] + code.values end

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
        extern #{type} #{name}GetNode(FinitaNode);
        extern void #{name}SetNode(#{type}, FinitaNode);
        void #{name}SetupEvaluator1() {
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
        FinitaMatrixCtor(&#{name}SymbolicMatrix, pow(size, 1.1));
        FinitaVectorCtor(&#{name}SymbolicVector, size);
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
            FinitaMatrixMerge(&#{name}SymbolicMatrix, row, column, (FinitaFp)#{code[fp].name});
            FinitaNodeSetPut(&#{name}Nodes, column);
          $
        end
        stream << %$
          FinitaVectorMerge(&#{name}SymbolicVector, row, (FinitaFp)#{code[eqn.rhs].name});
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
          if(!FinitaMatrixContainsKey(&#{name}SymbolicMatrix, key)) {
            FINITA_ASSERT(!FinitaVectorContainsKey(&#{name}SymbolicVector, node));
            FinitaMatrixPut(&#{name}SymbolicMatrix, key, NULL);
            FinitaVectorPut(&#{name}SymbolicVector, node, NULL);
          }
        }
      $
      stream << '}'
      stream << %$
        void #{name}SetupEvaluator2() {
          int i;
          FinitaEvaluatorEntry entry;
#if 1
          {
            FILE *f = fopen("#{name}SymbolicMatrix.dat", "wt");
            FinitaMatrixLog(&#{name}SymbolicMatrix, f);
            fclose(f);
          }
          {
            FILE *f = fopen("#{name}SymbolicVector.dat", "wt");
            FinitaVectorLog(&#{name}SymbolicVector, f);
            fclose(f);
          }
          {
            FILE *f = fopen("#{name}Nodes.dat", "wt");
            FinitaNodeSetLog(&#{name}Nodes, f);
            fclose(f);
          }
#endif
          #{name}MatrixEntry = (FinitaEvaluatorEntry*)FINITA_MALLOC(sizeof(FinitaEvaluatorEntry)*#{name}NNZ); FINITA_ASSERT(#{name}MatrixEntry);
          #{name}VectorEntry = (FinitaEvaluatorEntry*)FINITA_MALLOC(sizeof(FinitaEvaluatorEntry)*#{name}NEQ); FINITA_ASSERT(#{name}VectorEntry);
          for(i = 0; i < #{name}NNZ; ++i) {
            entry.row = FinitaMapperNode(&#{name}Mapper, #{name}LHS[i].row);
            entry.column = FinitaMapperNode(&#{name}Mapper, #{name}LHS[i].column);
            entry.fps = FinitaMatrixAt(&#{name}SymbolicMatrix, entry.row, entry.column);
            #{name}MatrixEntry[i] = entry;
          }
          for(i = 0; i < #{name}NEQ; ++i) {
            entry.row = entry.column = FinitaMapperNode(&#{name}Mapper, #{name}RHS[i].row);
            entry.fps = FinitaVectorAt(&#{name}SymbolicVector, entry.row);
            #{name}VectorEntry[i] = entry;
          }
        }
      $
    end

    def write_defs_linear(stream)
      stream << %$
      #{type} #{name}EvaluateMatrixEntry(FinitaFpList* fps, FinitaNode row, FinitaNode column) {
          if(fps) {
            FinitaFpListIt it;
            #{type} result = 0;
            FinitaFpListItCtor(&it, fps);
            while(FinitaFpListItHasNext(&it)) {
              result += ((#{name}Fp)FinitaFpListItNext(&it))(row.x, row.y, row.z);
            }
            return result;
          } else {
            return 1;
          }
        }
        #{type} #{name}EvaluateVectorEntry(FinitaFpList* fps, FinitaNode row) {
          if(fps) {
            #{type} result = 0;
            FinitaFpListIt it;
            FinitaFpListItCtor(&it, fps);
            while(FinitaFpListItHasNext(&it)) {
              result += ((#{name}Fp)FinitaFpListItNext(&it))(row.x, row.y, row.z);
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
        #{type} #{name}EvaluateMatrixEntry(FinitaFpList* fps, FinitaNode row, FinitaNode column) {
          if(fps) {
            FinitaFpListIt it;
            #{type} value, eta, result = 0, eps = 100*#{evaluator.relative_tolerance};
            value = #{name}GetNode(column);
            eta = fabs(value) > eps ? value*#{evaluator.relative_tolerance} : (value < 0 ? -1 : 1)*eps; /* from the PETSc's MatFD implementation '*/
            FinitaFpListItCtor(&it, fps);
            while(FinitaFpListItHasNext(&it)) {
              #{name}Fp fp = (#{name}Fp)FinitaFpListItNext(&it);
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
        #{type} #{name}EvaluateVectorEntry(FinitaFpList* fps, FinitaNode row) {
          if(fps) {
            FinitaFpListIt it;
            #{type} result = 0;
            FinitaFpListItCtor(&it, fps);
            while(FinitaFpListItHasNext(&it)) {
              result += ((#{name}Fp)FinitaFpListItNext(&it))(row.x, row.y, row.z);
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
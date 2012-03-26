require 'finita/common'
require 'finita/generator'


module Finita::Solver


class SolverCode < Finita::CodeTemplate

  attr_reader :gtor, :solver, :system, :name, :type

  def initialize(solver, gtor, system)
    @gtor = gtor
    @solver = solver
    @system = system
    @name = system.name
    @type = Finita::Generator::Scalar[system.type]
    gtor << self
  end

  def write_intf(stream)
    stream << %$
      void #{name}Solve();
      void #{name}SetupSolver();
    $
  end

end # SolverCode


class Explicit

  class Code < Finita::BoundCodeTemplate
    attr_reader :name, :type, :equations, :unknowns, :evaluator
    def entities; super + [Finita::Mapper::StaticCode.instance, VectorCode.instance] + evaluator.values end
    def initialize(solver, gtor, system)
      super({:solver=>solver}, gtor)
      raise 'Explicit solver requires non-linear system' if system.linear?
      @system = system
      @name = system.name
      @type = Finita::Generator::Scalar[system.type]
      @equations = system.equations
      @unknowns = system.unknowns
      @evaluator = {}
      equations.each do |eqn|
        eqn.bind(gtor)
        evaluator[eqn] = gtor << FpCode.new(eqn.rhs, eqn.type)
      end
    end
    def write_intf(stream)
      stream << %$
        void #{name}Solve();
        void #{name}SetupSolver();
      $
    end
    def write_defs(stream)
      stream << %$
        typedef #{type} (*#{name}Fp)(int, int, int);
        FinitaFpVector #{name}Evaluators;
      $
      stream << %$
        void #{name}SetupSolver() {
          int index, size;
          size = FinitaOrdererSize(&#{name}Orderer);
          FinitaFpVectorCtor(&#{name}Evaluators, &#{name}Orderer);
          for(index = 0; index < size; ++index) {
            int x, y, z;
            FinitaNode row = FinitaOrdererNode(&#{name}Orderer, index);
            x = row.x; y = row.y; z = row.z;
      $
      equations.each do |eqn|
        stream << "if(row.field == #{unknowns.index(eqn.unknown)} && #{gtor[eqn.domain].within_xyz}) {"
        stream << "FinitaFpVectorMerge(&#{name}Evaluators, index, (FinitaFp)#{evaluator[eqn].name});"
        stream << (eqn.through? ? '}' : 'continue;}')
      end
      stream << '}}'
      stream << %$
        void #{name}Solve() {
          int index, size = FinitaOrdererSize(&#{name}Orderer);
          FINITA_ASSERT(#{name}Orderer.frozen);
          for(index = 0; index < size; ++index) {
            FinitaFpListIt it;
            #{type} result = 0;
            FinitaNode node = FinitaOrdererNode(&#{name}Orderer, index);
            FinitaFpListItCtor(&it, FinitaFpVectorAt(&#{name}Evaluators, index));
            while(FinitaFpListItHasNext(&it)) {
              result += ((#{name}Fp)FinitaFpListItNext(&it))(node.x, node.y, node.z);
            }
            #{name}SetNode(result, node);
          }
        }
      $
    end
  end # Code

  def bind(gtor, system)
    Code.new(self, gtor, system) unless gtor.bound?(self)
  end

end if false # Explicit


class Matrix

  class Code < SolverCode

    def entities; super + [@evaluator_code, @backend_code] end

    def initialize(solver, gtor, system, evaluator_code, backend_code)
      super(solver, gtor, system)
      @evaluator_code = evaluator_code
      @backend_code = backend_code
    end

    def write_defs(stream)
      super
      stream << %$
        void #{name}SetupSolver() {
          #{name}SetupEvaluator1();
          #{name}SetupMapper();
          #{name}SetupBackend();
          #{name}SetupEvaluator2();
        }
      $
      if system.linear?
        stream << %$
          void #{name}Solve() {
            int i;
            for(i = 0; i < #{name}NNZ; ++i) {
              FinitaEvaluatorEntry entry = #{name}MatrixEntry[i];
              #{name}LHS[i].value = #{name}EvaluateMatrixEntry(entry.fps, entry.row, entry.column);
            }
            for(i = 0; i < #{name}NEQ; ++i) {
              FinitaEvaluatorEntry entry = #{name}VectorEntry[i];
              #{name}RHS[i].value = -#{name}EvaluateVectorEntry(entry.fps, entry.row);
            }
            #{name}SolveLinearSystem();
            for(i = 0; i < #{name}NEQ; ++i) {
              #{name}SetIndex(#{name}RHS[i].value, #{name}RHS[i].row);
            }
          }
        $
      else
        abs = :fabs if system.type == Float
        abs = :cabs if system.type == Complex
        stream << %$
          void #{name}Solve() {
            int i;
            #{type} norm;
            do {
              #{type} base = 0, delta = 0;
              for(i = 0; i < #{name}NNZ; ++i) {
                FinitaEvaluatorEntry entry = #{name}MatrixEntry[i];
                #{name}LHS[i].value = #{name}EvaluateMatrixEntry(entry.fps, entry.row, entry.column);
              }
              for(i = 0; i < #{name}NEQ; ++i) {
                FinitaEvaluatorEntry entry = #{name}VectorEntry[i];
                #{name}RHS[i].value = -#{name}EvaluateVectorEntry(entry.fps, entry.row);
              }
              #{name}SolveLinearSystem();
              for(i = 0; i < #{name}NEQ; ++i) {
                #{type} value = #{name}GetIndex(#{name}RHS[i].row);
                base += #{abs}(value);
                delta += #{abs}(#{name}RHS[i].value);
                #{name}SetIndex(value + #{name}RHS[i].value, #{name}RHS[i].row);
              }
              norm = (base == 0 ? 1 : delta/base); if(delta == 0) norm = 0;
            } while(norm > #{solver.relative_tolerance});
          }
        $
      end
    end
  end # Code

  attr_reader :evaluator, :backend

  attr_reader :relative_tolerance

  def initialize(rtol, evaluator, backend)
    @relative_tolerance = rtol
    @evaluator = evaluator
    @backend = backend
  end

  def bind(gtor, system)
    Code.new(self, gtor, system, evaluator.bind(gtor, system), backend.bind(gtor, system))
  end

end # Matrix


end # Finita::Solver
require 'finita/common'
require 'finita/generator'


module Finita::Solver


class Explicit

  class Code < Finita::BoundCodeTemplate
    attr_reader :name, :type, :equations, :unknowns, :evaluator
    def entities; super + [Finita::Ordering::StaticCode.instance, FpVectorCode.instance] + evaluator.values end
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
        evaluator[eqn] = gtor << EvaluatorCode.new(eqn.rhs, eqn.type)
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
        void #{name}SolverSetup() {
          int index;
          FINITA_ASSERT(#{name}Ordering.frozen);
          FinitaFpVectorCtor(&#{name}Evaluators, &#{name}Ordering);
          for(index = 0; index < #{name}Ordering.linear_size; ++index) {
            int x, y, z;
            FinitaNode row = #{name}Ordering.linear[index];
            x = row.x; y = row.y; z = row.z;
      $
      equations.each do |eqn|
        stream << "if(row.field == #{unknowns.index(eqn.unknown)} && #{gtor[eqn.domain].within_xyz}) {"
        stream << "FinitaFpVectorMerge(&#{name}Evaluators, index, (FinitaFp)#{evaluator[eqn].name});"
        stream << (eqn.through? ? '}' : 'break;}')
      end
      stream << '}}'
      stream << %$
        void #{name}Solve() {
          int index, size = FinitaOrderingSize(&#{name}Ordering);
          FINITA_ASSERT(#{name}Ordering.frozen);
          for(index = 0; index < size; ++index) {
            FinitaFpListIt it;
            #{type} result = 0;
            FinitaNode node = FinitaOrderingNode(&#{name}Ordering, index);
            FinitaFpListItCtor(&it, FinitaFpVectorGet(&#{name}Evaluators, index));
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

end # Explicit


end # Finita::Solver
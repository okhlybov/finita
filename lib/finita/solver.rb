require 'finita/common'
require 'finita/system'
require 'finita/evaluator'
require 'finita/mapper'


module Finita


class Solver
  attr_reader :mapper
  def initialize(mapper)
    @mapper = mapper
  end
  def code(problem_code, system_code)
    self.class::Code.new(self, problem_code, system_code)
  end
  class Code < DataStruct::Code
    attr_reader :solver
    def initialize(solver, problem_code, system_code)
      @solver = solver
      @problem_code = problem_code
      @system_code = system_code
      @system_code.initializers << self
      super("#{@system_code.type}Solver")
    end
    def hash
      solver.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && self.solver == other.solver
    end
  end # Code
end # Solver


class Solver::Explicit < Solver
  attr_reader :evaluators
  def process!(problem, system)
    mapper.process!(system)
    @evaluators = system.equations.collect {|e| [Finita::Evaluator.new(e.assignment.expression, system.type), e.domain]}
  end
  class Code < Solver::Code
    def entities; super + [@mapper_code, @array] end # + @evaluator_codes.flatten
    def initialize(*args)
      super
      @node = NodeCode.instance
      @array = EvaluationArrayCode[@system_code.system.type]
      @mapper_code = solver.mapper.code(@problem_code, @system_code)
      @evaluator_codes = solver.evaluators.collect {|e| [e.first.code(@problem_code), e.last.code(@problem_code)]}
    end
    def write_intf(stream)
      stream << %$
        int #{setup}(void);
      $
    end
    def write_defs(stream)
      stream << %$
        static #{@array.type} #{evaluators};
        int #{setup}(void) {
          return FINITA_OK;
        }
        int #{@system_code.solve}(void) {
          return FINITA_OK;
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end
end # Explicit


end # Finita
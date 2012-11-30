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
      @system_code.finalizers << self
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
    @evaluators = system.equations.collect {|e| Finita::Evaluator.new(e.assignment.expression, system.type)}
  end
  class Code < Solver::Code
    def entities; super + [solver.mapper.code(@problem_code, @system_code)] + solver.evaluators.collect {|e| e.code(@problem_code)} end
    def write_defs(stream)
      stream << %$
        int #{@system_code.solve}(void) {
          return FINITA_OK;
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{assert}(result == FINITA_OK);$
    end
    def write_finalizer(stream)
      stream << %$#{assert}(result == FINITA_OK);$
    end
  end
end # Explicit


end # Finita
require "autoc"
require "finita/evaluator"


module Finita


class Jacobian
  def process!(solver)
    @solver = check_type(solver, Solver::Matrix)
    self
  end
  attr_reader :solver
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < DataStructBuilder::Code
    def initialize(jacobian, solver_code)
      @jacobian = check_type(jacobian, Jacobian)
      @solver_code = check_type(solver_code, Solver::Matrix::Code)
      super("#{solver_code.system_code.type}Jacobian")
    end
    def entities
      super + [NodeCode] + solver_code.all_dependent_codes
    end
    attr_reader :solver_code
    def hash
      @jacobian.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @jacobian == other.instance_variable_get(:@jacobian)
    end
    def write_intf(stream)
      stream << %$#{solver_code.system_code.cresult} #{evaluate}(#{NodeCode.type}, #{NodeCode.type});$
    end
  end # Code
end # Jacobian


end # Finita


require "finita/jacobian/numeric"
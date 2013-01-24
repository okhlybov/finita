require 'finita/common'
require 'finita/system'
require 'finita/evaluator'
require 'finita/mapper'
require 'finita/environment'


require 'finita/jacobian'
require 'finita/residual'
require 'finita/lhs'
require 'finita/rhs'



module Finita


class Solver
  include EnvironmentHandler
  attr_reader :mapper, :environment
  def initialize(mapper, environment)
    @mapper = mapper
    @environment = environment
  end
  def process!(problem, system)
    setup_env(environment)
    mapper.process!(problem, system, self)
    self
  end
  def code(problem_code, system_code)
    self.class::Code.new(self, problem_code, system_code)
  end
  class Code < DataStruct::Code
    def entities; super + [@node, @environment_code] end
    def initialize(solver, problem_code, system_code)
      @solver = solver
      @node = NodeCode
      @coord = NodeCoordCode
      @problem_code = problem_code
      @system_code = system_code
      @mapper_code = solver.mapper.code(@problem_code, @system_code)
      @environment_code = solver.environment.code(problem_code)
      @system_code.initializers << self
      super("#{@system_code.type}Solver")
    end
    def hash
      @solver.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @solver == other.instance_variable_get(:@solver)
    end
    def write_intf(stream)
      stream << %$int #{@system_code.solve}(void);$
    end
  end # Code
end # Solver


class Solver::Matrix < Solver
  attr_reader :jacobian
  def residual
    @residual.nil? ? @residual = Residual.new : @residual
  end
  def lhs
    @lhs.nil? ? @lhs = LHS.new : @lhs
  end
  def lhs=(lhs)
    @lhs = lhs
  end
  def rhs
    @rhs.nil? ? @rhs = RHS.new : @rhs
  end
  def rhs=(rhs)
    @rhs = rhs
  end
  def nonlinear!
    @force_nonlinear = true
  end
  def initialize(mapper, environment, jacobian, &block)
    super(mapper, environment)
    @jacobian = jacobian
    block.call(self) if block_given?
  end
  def linear?
    @linear && !@force_nonlinear
  end
  def process!(problem, system)
    super
    @linear = system.linear?
    if linear?
      lhs.process!(problem, system)
      rhs.process!(problem, system)
    else
      jacobian.process!(problem, system)
      residual.process!(problem, system)
    end
    self
  end
  class Code < Solver::Code
    def entities; super + [@matrix_code, @vector_code] end
    def initialize(*args)
      super
      if @solver.linear?
        @matrix_code = @solver.lhs.code(@problem_code, @system_code, @mapper_code)
        @vector_code = @solver.rhs.code(@problem_code, @system_code, @mapper_code)
      else
        @matrix_code = @solver.jacobian.code(@problem_code, @system_code, @mapper_code)
        @vector_code = @solver.residual.code(@problem_code, @system_code, @mapper_code)
      end
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end # Code
end # Matrix


end # Finita


require 'finita/solver/explicit'
require 'finita/solver/petsc'
require 'finita/solver/mumps'
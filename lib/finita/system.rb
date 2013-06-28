require "autoc"
require "finita/problem"
require "finita/equation"
require "finita/solver"
require "finita/discretizer"


module Finita


class System
  @@current = nil
  def self.current
    raise "system context is not set" if @@current.nil?
    @@current
  end
  def self.current=(system)
    raise "nested system contexts are not allowed" if @@current.nil? == system.nil?
    @@current = system
  end
  def initialize(name, &block)
    @name = name.to_s # TODO validate
    @equations = []
    @problem = Problem.current
    @problem.systems << self
    if block_given?
      begin
        System.current = self
        block.call(self)
      ensure
        System.current = nil
      end
    end
  end
  attr_reader :name
  attr_reader :equations
  def solver=(solver)
    @solver = check_type(solver, Solver)
  end
  def solver
    if @solver.nil?
      raise "system-wise solver is not specified"
    else
      @solver
    end
  end
  def discretizer=(discretizer)
    @discretizer = discretizer # check_type(discretizer, Discretizer)
  end
  def discretizer
    if @discretizer.nil?
      raise "system-wise discretizer is not specified"
    else
      @discretizer
    end
  end
  def result
    Numeric.promoted_type(*equations.collect {|s| s.type})
  end
  def unknowns
    Set.new(equations.collect {|e| e.unknown})
  end
  def linear?
    @linear
  end
  attr_reader :problem
  def process!(problem)
    @problem = check_type(problem, Problem)
    @equations = discretizer.process!(equations)
    @linear = true
    equations.each do |e|
      unless e.decomposition(unknowns).linear?
        @linear = false
        break
      end
    end
    @solver = solver.process!(self)
    self
  end
  def code(problem_code)
    self.class::Code.new(self, problem_code)
  end
  class Code < DataStructBuilder::Code
    def initialize(system, problem_code)
      @system = check_type(system, System)
      @problem_code = check_type(problem_code, Problem::Code)
      @initializer_codes = Set.new
      @finalizer_codes = Set.new
      super("#{problem_code.type}#{@system.name}")
      @solver_code = check_type(@system.solver.code(self), Solver::Code)
      @equation_codes = @system.equations.collect {|e| check_type(e.code(problem_code), Binding::Algebraic::Code)}
      problem_code.initializer_codes << self
      problem_code.finalizer_codes << self
    end
    def entities
      @entities.nil? ? @entities = [solver_code] + equation_codes + (initializer_codes | finalizer_codes).to_a : @entities
    end
    attr_reader :initializer_codes
    attr_reader :finalizer_codes
    attr_reader :problem_code
    attr_reader :solver_code
    attr_reader :equation_codes
    def linear?
      @system.linear?
    end
    def result
      @system.result
    end
    def cresult
      CType[result]
    end
    def integer?
      result == Integer
    end
    def float?
      result == Float
    end
    def complex?
      result == Complex
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
    def write_finalizer(stream)
      stream << %$#{cleanup}();$
    end
    def write_defs(stream)
      stream << %$void #{setup}(void) {FINITA_ENTER;$
      CodeBuilder.priority_sort(initializer_codes, false).each do |e|
        e.write_initializer(stream)
      end
      stream << "FINITA_LEAVE;}"
      stream << %$void #{cleanup}(void) {FINITA_ENTER;$
      CodeBuilder.priority_sort(finalizer_codes, true).each do |e|
        e.write_finalizer(stream)
      end
      stream << "FINITA_LEAVE;}"
    end
  end # Code
end # System


end # Finita
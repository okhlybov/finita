require 'data_struct'
require 'finita/problem'
require 'finita/equation'
require 'finita/solver'
require 'finita/discretizer'


module Finita


class System
  @@current = nil
  def self.current
    raise 'system context is not set' if @@current.nil?
    @@current
  end
  def self.current=(system)
    raise 'nested system contexts are not allowed' if @@current.nil? == system.nil?
    @@current = system
  end
  attr_reader :name, :equations
  attr_accessor :solver, :discretizer
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
  def type
    Numeric.promoted_type(*equations.collect {|s| s.type})
  end
  def integer?
    type == Integer
  end
  def float?
    type == Float
  end
  def complex?
    type == Complex
  end
  def unknowns
    Set.new(equations.collect {|e| e.unknown})
  end
  def linear?
    @linear
  end
  def process!
    uns = unknowns
    @equations = discretizer.process!(equations)
    @linear = true
    equations.each do |e|
      unless e.decomposition(uns).linear?
        @linear = false
        break
      end
    end
    @solver = solver.process!(@problem, self)
    self
  end
  def code(problem_code)
    self.class::Code.new(self, problem_code)
  end
  class Code < DataStruct::Code
    attr_reader :unknowns, :initializers, :finalizers, :result
    def entities; super + [SparseMatrix.new('SM', Float).code(@problem_code, self), solver_code] + equation_codes + (initializers | finalizers).to_a end
    def initialize(system, problem_code)
      @system = system
      @problem_code = problem_code
      @initializers = Set.new
      @finalizers = Set.new
      @result = CType[system.type]
      @problem_code.initializers << self
      @problem_code.finalizers << self
      @problem_code.defines << :FINITA_COMPLEX if complex?
      @unknowns = @system.unknowns # FIXME shouldnt be exposed
      super(@problem_code.type + system.name)
    end
    def hash
      @system.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @system == other.instance_variable_get(:@system)
    end
    def system_type # TODO rename
      @system.type
    end
    def integer?
      @system.integer?
    end
    def float?
      @system.float?
    end
    def complex?
      @system.complex?
    end
    def solver_code
      @system.solver.code(@problem_code, self)
    end
    def equation_codes
      @system.equations.collect {|e| e.code(@problem_code, self)}
    end
    def write_intf(stream)
      stream << %$
        int #{setup}(void);
        int #{cleanup}(void);
      $
    end
    def write_defs(stream)
      stream << %$int #{setup}(void) {int result = FINITA_OK;$
      CodeBuilder.priority_sort(initializers, false).each do |e|
        e.write_initializer(stream)
      end
      stream << 'return result;}'
      stream << %$int #{cleanup}(void) {int result = FINITA_OK;$
      CodeBuilder.priority_sort(finalizers, true).each do |e|
        e.write_finalizer(stream)
      end
      stream << 'return result;}'
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
    def write_finalizer(stream)
      stream << %$result = #{cleanup}(); #{assert}(result == FINITA_OK);$
    end
  end # Code
end # System


end # Finita
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
  attr_reader :name, :equations, :type
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
    Float # TODO
  end
  def process!
    @equations = discretizer.process!(equations)
    solver.process!(@problem, self)
  end
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < DataStruct::Code
    attr_reader :system, :initializers, :finalizers
    def entities; super + [system.solver.code(@problem_code, self)] + (initializers | finalizers).to_a end
    def initialize(system, problem_code)
      @system = system
      @problem_code = problem_code
      @initializers = Set.new
      @finalizers = Set.new
      @problem_code.initializers << self
      @problem_code.finalizers << self
      @problem_code.defines << :FINITA_COMPLEX if system.type == Complex
      super(@problem_code.type + system.name)
    end
    def hash
      system.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && system == other.system
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
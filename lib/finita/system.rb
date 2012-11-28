require 'data_struct'
require 'finita/problem'
#require 'finita/equation'


module Finita


class System
  @@current = nil
  def self.current
    raise 'system context is not set' if @@current.nil?
    @@current
  end
  def self.current=(system)
    raise 'nested system contexts are not allowed' if @@current.nil? == problem.nil?
    @@current = system
  end
  attr_reader :name, :equations, :problem
  def initialize(name, &block)
    @name = name.to_s # TODO validate
    @problem = Problem.current
    problem.systems << self
    if block_given?
      begin
        System.current = self
        block.call(self)
      ensure
        System.current = nil
      end
    end
  end
  def code(problem_code)
    Code.new(self, problem_code)
  end
end # System


class System::Code < DataStruct::Code
  attr_reader :system, :initializers, :finalizers
  def entities; super + (initializers | finalizers).to_a end
  def initialize(system, problem_code)
    @system = system
    super(system.problem.name + system.name)
    @initializers = Set.new
    @finalizers = Set.new
    problem_code.initializers << self
    problem_code.finalizers << self
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
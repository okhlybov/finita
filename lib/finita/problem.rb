require 'set'
require 'data_struct'
require 'finita/type'
require 'finita/system'
require 'finita/generator'


module Finita


class Problem
  @@current = nil
  @@problems = []
  def self.current
    raise 'problem context is not set' if @@current.nil?
    @@current
  end
  def self.current=(problem)
    raise 'nested problem contexts are not allowed' if @@current.nil? == problem.nil?
    @@current = problem
  end
  def self.problems
    @@problems
  end
  attr_reader :name, :systems, :instances
  def initialize(name, &block)
    @name = name.to_s # TODO validate
    @instances = Set.new
    @systems = []
    Problem.problems << self
    if block_given?
      begin
        Problem.current = self
        block.call(self)
      ensure
        Problem.current = nil
      end
    end
  end
  def <<(entity)
    instances << entity
  end
  def process!
    @module = new_module
    @module << code
    @module.generate!
  end
  def code
    Code.new(self)
  end
  protected
  def new_module
    Generator::Module.new(name)
  end
end # Problem


class Problem::Code < DataStruct::Code
  attr_reader :problem, :initializers, :finalizers
  def entities; super + @codes.values + (problem.systems + problem.instances.to_a).collect {|s| s.code(self)} + (initializers | finalizers).to_a end
  def initialize(problem)
    @problem = problem
    super(problem.name)
    @initializers = Set.new
    @finalizers = Set.new
    @symbols = {}
    @codes = {}
  end
  def hash
    problem.hash
  end
  def eql?(other)
    equal?(other) || self.class == other.class && problem == other.problem
  end
  def <<(code)
    if @codes.key?(code)
      @codes[code]
    else
      if code.respond_to?(:symbol)
        symbol = code.symbol
        raise "duplicate global symbol #{symbol}" if @symbols.key?(symbol) && @symbols[symbol] != code
        @symbols[symbol] = code
      end
      @codes[code] = code
    end
  end
  def write_intf(stream)
    stream << %$
        int #{setup}(int, char**);
        int #{cleanup}(void);
      $
  end
  def write_defs(stream)
    stream << %$
      FINITA_ARGSUSED
      int #{setup}(int argc, char** argv) {int result = FINITA_OK;
    $
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
end # Code


end # Finita
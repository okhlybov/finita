require "set"
require "autoc"
require "finita/symbolic"
require "finita/system"
require "finita/generator"


module Finita


class Problem
  @@current = nil
  @@problems = []
  def self.current
    raise "problem context is not set" if @@current.nil?
    @@current
  end
  def self.current=(problem)
    raise "nested problem contexts are not allowed" if @@current.nil? == problem.nil?
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
    @systems = systems.collect {|s| s.process!(self)}
    new_module(code).generate!
    self
  end
  def code
    self.class::Code.new(self)
  end
  class Code < Finita::Code
    def initialize(problem)
      @problem = Finita.check_type(problem, Problem)
      @initializer_codes = Set.new
      @finalizer_codes = Set.new
      @bound_codes = {}
      super(problem.name)
      @system_codes = @problem.systems.collect {|s| s.code(self)}
      @instance_codes = @problem.instances.collect {|i| i.code(self)}
    end
    attr_reader :initializer_codes
    attr_reader :finalizer_codes
    def entities
      super.concat(@bound_codes.values + @system_codes + @instance_codes + (initializer_codes | finalizer_codes).to_a)
    end
    def hash
      @problem.hash # TODO
    end
    def ==(other)
      equal?(other) || self.class == other.class && @problem == other.instance_variable_get(:@problem)
    end
    alias :eql? :==
    def bind!(owner, &ctor)
      @bound_codes.include?(owner) ? @bound_codes[owner] : @bound_codes[owner] = yield(self)
    end
    def write_intf(stream)
      stream << %$
        #{extern} void #{setup}(int, char**);
        #{extern} void #{cleanup}(void);
      $
    end
    def write_defs(stream)
      ###
      stream << %$
        FINITA_ARGSUSED
        void #{setup}(int argc, char** argv) {FINITA_ENTER;$
      system_codes = []
      other_codes = []
      AutoC.priority_sort(initializer_codes, false).each do |c|
        if c.is_a?(Finita::System::Code)
          system_codes << c
        else
          other_codes << c
        end
      end
      other_codes.each { |c| c.write_initializer(stream) }
      stream << "\n#pragma omp parallel sections\n{"
      system_codes.each do |c|
        stream << "\n#pragma omp section\n"
        c.write_initializer(stream)
      end
      stream << "}"
      stream << "FINITA_LEAVE;}"
      ###
      stream << %$void #{cleanup}(void) {FINITA_ENTER;$
      system_codes = []
      other_codes = []
      AutoC.priority_sort(finalizer_codes, true).each do |c|
        if c.is_a?(Finita::System::Code)
          system_codes << c
        else
          other_codes << c
        end
      end
      stream << "\n#pragma omp parallel sections\n{"
      system_codes.each do |c|
        stream << "\n#pragma omp section\n"
        c.write_finalizer(stream)
      end
      stream << "}"
      other_codes.each { |c| c.write_finalizer(stream) }
      stream << "FINITA_LEAVE;}"
    end
  end # Code
  private
  def new_module(root_code)
    AutoC::Module.new(name) << root_code
  end
end # Problem


end # Finita
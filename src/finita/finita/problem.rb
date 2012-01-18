require 'set'
require 'code_builder'
require 'finita/common'
require 'finita/generator'


module Finita


# This class represents the root in the hierarchy of the problem specified.
class Problem

  @@object = nil

  # Return current problem object which is set when the Problem constructor is supplied with block.
  def self.object
    raise 'Problem context is not set' if @@object.nil?
    @@object
  end

  class Code < BoundCodeTemplate
    def entities; super + [Generator::StaticCode.instance, @setup, @cleanup, CoordSetCode.instance] end
    def initialize(master, gtor)
      super(master, gtor)
      @setup = BoundFunctionCode.new("#{master.name}Setup", ['int argc', 'char** argv'], 'void', :write_setup, gtor)
      @cleanup = BoundFunctionCode.new("#{master.name}Cleanup", [], 'void', :write_cleanup, gtor)
    end
  end # Code

  # Return problem name as seen from the C side.
  # Must be a valid C identifier.
  attr_reader :name

  # Return list of equation systems bound to the problem.
  # The list ordering is not important.
  attr_reader :systems

  # Return problem-wise backend.
  # This backend is to be used by the systems bound to this problem for which system-specific backends are not specified.
  def backend
    raise 'Problem-wise backend is not set' if @backend.nil?
    @backend
  end

  # Set problem-wise backend. See #backend.
  def backend=(backend)
    @backend = backend
  end

  # Initialize a new problem instance.
  # Invokes #process when optional block is supplied.
  def initialize(name, &block)
    @name = name
    @systems = []
    if block_given?
      raise 'Problem nesting is not permitted' unless @@object.nil?
      begin
        @@object = self
        yield(self)
      ensure
        @@object = nil
      end
      process
    end
  end

  # Generate source code for the problem.
  def process
    new_generator.generate
  end

  # Bind code entities to specified generator.
  # Invokes bind() methods on owned sub-objects.
  def bind(gtor)
    Code.new(self, gtor)
    systems.each {|s| s.bind(gtor)}
  end

  protected

  # Return new instance of generator to be used for code generation.
  # The generator is expected to be bound to this object.
  # This implementation returns a Finita::Generator instance.
  # Used by #process.
  def new_generator
    Finita::Generator.new(self)
  end

end # Problem


end # Finita
require 'set'
require 'code_builder'
require 'finita/common'
require 'finita/generator'
require 'finita/ordering'


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
    def entities; super + [Generator::StaticCode.instance, @setup, @cleanup] end
    def initialize(master, gtor)
      super(master, gtor)
      @setup = CustomFunctionCode.new(gtor, "#{master.name}Setup", ['int argc', 'char** argv'], 'void', :write_setup)
      @cleanup = CustomFunctionCode.new(gtor, "#{master.name}Cleanup", [], 'void', :write_cleanup)
    end
  end # Code

  # Return problem name as seen from the C side.
  # Must be a valid C identifier.
  attr_reader :name

  # Return list of equation systems bound to the problem.
  # The list ordering is not important.
  attr_reader :systems

  # Return problem-wise solver.
  # This solver is to be used by the systems bound to this problem for which system-specific backends are not specified.
  def solver
    @solver.nil? ? raise('Problem-wise algebraic solver is not set') : @solver
  end

  # Set problem-wise solver. See #solver.
  def solver=(solver)
    @solver = solver
  end

  def transformer
    @t9r.nil? ? raise('Problem-wise coordinate transformer is not set') : @t9r
  end

  def transformer=(t9r)
    @t9r = t9r
  end

  def discretizer
    @d9r.nil? ? raise('Problem-wise discretizer is not set') : @d9r
  end

  def discretizer=(d9r)
    @d9r = d9r
  end

  def generator
    @gtor.nil? ? generator = Generator::Default.new : @gtor
  end

  def generator=(gtor)
    @gtor = gtor
  end

  def ordering
    @ordering.nil? ? raise('Problem-wise ordering is not set') : @ordering
  end

  def ordering=(ordering)
    @ordering = ordering
  end

  def parallel?
    @parallel
  end

  def parallel=(bool)
    @parallel = bool
  end

  # Initialize a new problem instance.
  # Invokes #process when optional block is supplied.
  def initialize(name, &block)
    @name = Finita.to_c(name)
    @systems = []
    parallel = false
    if block_given?
      raise 'Problem nesting is not permitted' unless @@object.nil?
      begin
        @@object = self
        yield(self)
      ensure
        @@object = nil
      end
      process!
    end
  end

  def unknowns
    set = Set.new
    systems.unknowns.each {|uns| set.merge(uns)}
    set
  end

  # Generate source code for the problem.
  def process!
    systems.each do |system|
      system.process!
    end
    generator.generate!(self)
  end

  # Bind code entities to specified generator.
  # Invokes bind() methods on owned sub-objects.
  def bind(gtor)
    Code.new(self, gtor) unless gtor.bound?(self)
    systems.each {|s| s.bind(gtor)}
  end

end # Problem


end # Finita
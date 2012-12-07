require 'symbolic'
require 'finita/symbolic'
require 'finita/domain'


module Finita


class Binding
  attr_reader :expression, :unknown, :domain
  def initialize(expression, unknown, domain, merge)
    raise 'invalid field value' unless unknown.is_a?(Field)
    @expression = Symbolic.coerce(expression)
    @unknown = unknown
    @domain = domain
    @merge = merge
    System.current.equations << self
  end
  def merge?; @merge end
  # def linear?(variable = field)
  # def assignment()
  def code(problem_code, system_code)
    Code.new(self, problem_code, system_code)
  end
  def process!
    @expression = Finita.simplify(Ref::Merger.new.apply!(expression))
  end
  class Code < DataStruct::Code
    attr_reader :binding
    def entities; super + [unknown_code, domain_code] end
    def initialize(binding, problem_code, system_code)
      @binding = binding
      @problem_code = problem_code
      @system_code = system_code
      super("#{system_code.type}Binding")
    end
    def hash
      binding.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && binding == other.binding
    end
    def unknown_code
      binding.unknown.code(@problem_code)
    end
    def domain_code
      binding.domain.code(@problem_code)
    end
  end
end # Binding


# Equation of form expression=field, where expression might be a function of unknown
class Assignment < Binding
  def initialize(hash, domain)
    # hash := {expression => unknown}
    raise 'expected {expression=>unknown} value' unless hash.is_a?(Hash) && hash.size == 1
    expression = hash.keys[0]
    unknown = hash[expression]
    super(expression, unknown, domain, false)
  end
  def assignment
    self
  end
end # Assignment


# Equation of form expression=0 with expression being a function of unknown
class Equation < Binding
  attr_reader :system
  def initialize(lhs, unknown, domain, merge = false)
    super
    @system = System.current
    system.equations << self
  end
  def assignment
    raise 'could not convert equation into assignment' # TODO
  end
end # Equation


end # Finita
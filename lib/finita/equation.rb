require 'symbolic'
require 'finita/type'
require 'finita/domain'


module Finita


class Binding
  attr_reader :expression, :field, :domain
  def initialize(expression, field, domain, merge)
    raise 'invalid field value' unless field.is_a?(Field)
    @expression = Symbolic.coerce(expression)
    @field = field
    @domain = domain
    @merge = merge
    System.current.equations << self
  end
  def merge?; @merge end
  # def linear?(variable = field)
  # def assignment()
end # Binding


# Equation of form expression=field, where expression might be a function of field
class Assignment < Binding
  def initialize(hash, domain)
    # hash := {expression => field}
    raise 'expected {expression=>field} value' unless hash.is_a?(Hash) && hash.size == 1
    expression = hash.keys[0]
    field = hash[expression]
    super(expression, field, domain, false)
  end
  def assignment
    self
  end
end # Assignment


# Equation of form expression=0 with expression being a function of field
class Equation < Binding
  attr_reader :system
  def initialize(lhs, field, domain, merge = false)
    super
    @system = System.current
    system.equations << self
  end
  def assignment
    raise 'could not convert equation into assignment' # TODO
  end
end # Equation


end # Finita
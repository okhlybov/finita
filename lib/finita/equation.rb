require 'symbolic'
require 'finita/common'
require 'finita/symbolic'
require 'finita/domain'


module Finita


class Decomposition < Hash
  def initialize(expression, unknowns)
    super()
    @expression = expression
    @unknowns = unknowns
    decompose
  end
  def linear?; @linear end
  private
  def decompose
    map = {}
    map.default = 0
    e = Symbolic.expand(@expression)
    (e.is_a?(Symbolic::Add) ? e.args : [e]).each do |t|
      unknown_refs = Collector.new.apply!(t).refs.delete_if {|r| !@unknowns.include?(r.arg)}
      if unknown_refs.size == 1
        r = unknown_refs.to_a.first
        term = ProductExtractor.new.apply!(t, r)
        if term.nil?
          map[nil] += t
        else
          map[r] += term
        end
      else
        map[nil] += t
      end
    end
    fc = ObjectCollector.new(Field)
    map.each do |r,e|
      fc.apply!(self[r] = Finita.simplify(e))
    end
    @linear = true
    fc.objects.each do |f|
      if @unknowns.include?(f)
        @linear = false
        break
      end
    end
  end
end # Decomposition


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
  def type
    TypeInferer.new.apply!(unknown)
  end
  def merge?; @merge end
  # def equation()
  # def assignment()
  def decomposition(unknowns)
    Decomposition.new(equation, unknowns) # TODO cache the result
  end
  def process!
    @expression = Finita.simplify(Ref::Merger.new.apply!(expression))
  end
  def code(problem_code, system_code)
    Code.new(self, problem_code, system_code)
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
    expression
  end
  def equation
    expression - Ref.new(unknown)
  end
end # Assignment


# Equation of form expression=0 with expression being a function of unknown
class Equation < Binding
  def initialize(lhs, unknown, domain, merge = false)
    super
    System.current.equations << self
  end
  def equation
    expression
  end
  def assignment
    raise # TODO
  end
end # Equation


end # Finita
require 'forwardable'
require 'finita/common'
require 'finita/system'
require 'finita/symbolic'
require 'finita/generator'


module Finita


module EquationMixin

  attr_reader :expression, :unknown, :domain, :system

  def initialize(expression, unknown, domain, through, system)
    @expression = expression
    @unknown = unknown
    @domain = domain
    @through = through
    @system = system
  end

  def through?
    @through
  end

  def type
    unknown.type
  end

end


class Equation

  include EquationMixin

  def initialize(expression, unknown, domain, through, system = Finita::System.object, &block)
    super(expression, unknown, domain, through, system)
    system.equations << self
    if block_given?
      yield(self)
    end
  end

end


class FpCode < FunctionTemplate
  @@index = 0
  attr_reader :name, :expression, :type
  def initialize(expression, type)
    @name = "_#{@@index += 1}"
    @expression = expression
    @type = type
    super(name, ['int x','int y','int z'], Generator::Scalar[type], true)
  end
  def hash
    self.class.hash ^ (expression.hash << 1) ^ (type.hash << 2)
  end
  def ==(other)
    equal?(other) || self.class == other.class && expression == other.expression && type == other.type
  end
  alias :eql? :==
  def write_body(stream)
    stream << "return #{CEmitter.new.emit!(expression)};"
  end
end


class AlgebraicEquation

  include EquationMixin

  attr_reader :lhs, :rhs

  def linear?
    @linear
  end

  def linearize!
    lhs = {}
    rhs = 0
    @linear = true
    @unknowns = system.unknowns
    expanded = Symbolic.expand(expression)
    (expanded.is_a?(Symbolic::Add) ? expanded.args : [expanded]).each do |term|
      product = split_term(term)
      if product.nil?
        @linear = false
        return
      end
      ref, rest = product
      if ref.nil?
        rhs += rest
      else
        lhs[ref] = lhs.has_key?(ref) ? lhs[ref] + rest : rest
      end
    end
    @lhs_ = lhs
    @rhs_ = rhs
  end

  def setup!
    @lhs = {}
    if system.linear?
      @lhs_.each {|k,v| @lhs[k] = Symbolic.simplify(v)}
      @rhs = Symbolic.simplify(@rhs_)
    else
      @rhs = Symbolic.simplify(expression) # this may be very time-consuming therefore consider applying the non-exhaustive simplification pass
      refs = RefCollector.new(@unknowns).collect!(@rhs)
      expanded = Symbolic.expand(rhs)
      evalers = {}
      (expanded.is_a?(Symbolic::Add) ? expanded.args : [expanded]).each do |term|
        refs.each do |ref|
          if RefDetector.new(ref).detected?(term)
            evalers[ref] = evalers.has_key?(ref) ? evalers[ref] + term : term
          end
        end
      end
      evalers.each {|k,v| @lhs[k] = Symbolic.simplify(v)}
    end
  end

  def bind(gtor)
    domain.bind(gtor)
    exs = [unknown, rhs] # assuming the non-linear system contains the whole expression in rhs
    exs.concat(lhs.values) if system.linear?
    ExpressionCollector.new(*exs).expressions.each {|e| e.bind(gtor)}
  end

  private

  def split_term(term)
    refs = []
    rest = []
    (term.is_a?(Symbolic::Multiply) ? term.args : [term]).each do |arg|
      if arg.is_a?(Ref) && arg.arg.is_a?(Field)
        (@unknowns.include?(arg.arg) ? refs : rest) << arg
      else
        rest << arg
      end
    end
    rc = RefCollector.new(@unknowns)
    rest.each {|term| term.apply(rc)}
    return nil unless rc.refs.empty?
    return nil if refs.size > 1
    if refs.empty?
      return [nil, Symbolic::Multiply.make(*rest)]
    elsif refs.size == 1
      return [refs.first, Symbolic::Multiply.make(*rest)]
    else
      return nil
    end
  end

end


end # Finita
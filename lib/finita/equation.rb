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


class AlgebraicEquation

  class EvaluatorCode < FunctionTemplate
    @@index = 0
    attr_reader :name, :expression, :type
    def initialize(master)
      @name = "_#{@@index += 1}"
      @expression = master.expression
      @type = master.type
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

  include EquationMixin

  def linear?
    false # TODO
  end

  def bind(gtor)
    domain.bind(gtor)
    ExpressionCollector.new(expression, unknown).expressions.each {|e| e.bind(gtor)}
    gtor << EvaluatorCode.new(self)
  end

end


end # Finita
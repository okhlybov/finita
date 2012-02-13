require 'finita/common'
require 'finita/system'
require 'finita/generator'

module Finita


class AbstractEquation

  attr_reader :lhs, :unknown, :domain, :system

  def initialize(lhs, unknown, domain, system, through)
    @lhs = lhs
    @unknown = unknown
    @domain = domain
    @system = system
    @through = through
  end

  def through?
    @through
  end

  def type
    unknown.type
  end

  def bind(gtor)
    unknown.bind(gtor)
    domain.bind(gtor)
    ExpressionCollector.new(lhs).expressions.each {|e| e.bind(gtor)}
  end

end # AbstractEquation


class Equation < AbstractEquation

  def initialize(lhs, unknown, domain, through, system = Finita::System.object, &block)
    super(lhs, unknown, domain, system, through)
    system.equations << self
    if block_given?
      yield(self)
    end
  end

  def discretizer
    @d9r.nil? ? problem.discretizer : @d9r
  end

  def discretizer=(d9r)
    @d9r = d9r
  end

end # Equation


class AlgebraicEquation < AbstractEquation

  class EvaluatorCode < FunctionTemplate
    @@index = 0
    attr_reader :name, :expression, :type
    def initialize(master)
      @name = "_#{@@index += 1}"
      @expression = master.lhs
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

  class Code < BoundCodeTemplate
    attr_reader :evaluator
    def entities; super + [evaluator] end
    def initialize(master, gtor)
      super
      @evaluator = gtor << EvaluatorCode.new(master)
    end
  end

  def bind(gtor)
    super
    Code.new(self, gtor) unless gtor.bound?(self)
  end

end # AlgebraicEquation


end # Finita
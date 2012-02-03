require 'finita/common'
require 'finita/system'
require 'finita/generator'

module Finita


class AbstractEquation

  attr_reader :lhs, :unknown, :domain, :system

  def initialize(lhs, unknown, domain, system)
    @lhs = lhs
    @unknown = unknown
    @domain = domain
    @system = system
  end

  def type
    unknown.type
  end

  def bind(gtor)
    unknown.bind(gtor)
    domain.bind(gtor)
    # TODO lhs
  end

end # AbstractEquation


class Equation < AbstractEquation

  def initialize(lhs, unknown, domain, system = Finita::System.object, &block)
    super(lhs, unknown, domain, system)
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

  class ChunkCode < FunctionTemplate
    @@index = 0
    attr_reader :name
    def initialize(master)
      @lhs = master.lhs
      @type = master.type
      @name = "_#{@@index+=1}"
      super(name, ['int x','int y','int z'], Generator::Scalar[@type], true)
    end
    def write_body(stream)
      stream << "return #{CEmitter.new.emit!(@lhs)};"
    end
  end

  class Code < BoundCodeTemplate
    attr_reader :chunk
    def entities; [chunk] end
    def initialize(master, gtor)
      super
      @chunk = ChunkCode.new(master)
    end
  end

  def bind(gtor)
    super
    Code.new(self, gtor)
  end

end # AlgebraicEquation


end # Finita
require 'singleton'
require 'symbolic'


#
class Symbolic::Expression
  def to_s
    emitter = Finita::Emitter.new
    apply(emitter)
    emitter.to_s
  end
  def [](*args)
    Finita::Ref.new(self, *args)
  end
end


module Finita


#
def self.to_c(obj)
  obj.to_s # TODO validate a C identifier
end


module ExpressionMethodStubs
  def convert; self end
  def expand; self end
  def collect; self end
  def revert; self end
end

#
class Scalar < Symbolic::Expression

  include ExpressionMethodStubs

  class Code < BoundCodeTemplate
    def write_intf(stream)
      stream << "extern #{Generator::Scalar[master.type]} #{master.name};"
    end
    def write_defs(stream)
      stream << "#{Generator::Scalar[master.type]} #{master.name};"
    end
  end # Code

  attr_reader :name, :type
  def initialize(name, type)
    @name = Finita.to_c(name)
    @type = type
  end
  def ==(other)
    self.class == other.class && name == other.name && type == other.type
  end
  def hash
    name.hash ^ type.hash
  end
  def apply(obj)
    obj.scalar(self)
  end
  def bind(gtor)
    Code.new(self, gtor)
  end
end # Scalar


#
class Field < Symbolic::Expression

  include ExpressionMethodStubs

  class Code < BoundCodeTemplate
    def grid_code; gtor[master.grid] end
    def entities; [grid_code] end
    def write_intf(stream)
      grid_code.write_field_intf(stream, master)
    end
    def write_defs(stream)
      grid_code.write_field_defs(stream, master)
    end
    def write_setup(stream)
      grid_code.write_field_setup(stream, master)
    end
    def node_count_s
      grid_code.node_count_s
    end
  end # Code

  attr_reader :name, :type, :grid

  def initialize(name, type, grid)
    @name = Finita.to_c(name)
    @type = type
    @grid = grid
  end
  def ==(other)
    self.class == other.class && name == other.name && type == other.type && grid == other.grid
  end
  def hash
    name.hash ^ type.hash ^ grid.hash
  end
  def apply(obj)
    obj.field(self)
  end
  def bind(gtor)
    grid.bind(gtor)
    Code.new(self, gtor)
  end
end # Field


class SymbolCollector < Symbolic::Traverser
  attr_reader :symbols
  def initialize()
    @symbols = Set.new
  end
  def symbol(obj)
    @symbols << obj
  end
  def ref(op)
    traverse_unary(obj)
  end
  def method_missing(*args) end
end # SymbolCollector


class Ref < Symbolic::UnaryFunction

  CoordSymbols = Set.new([:x, :y, :z])

  class Offsets < Hash
    def []=(key, value)
      raise 'invalid offset symbol' unless CoordSymbols.include?(key)
      raise 'duplicate offset symbol' if include?(key)
      super
    end
  end # Offsets

  attr_reader :xref, :yref, :zref

  def initialize(op, *args)
    super(op)
    offs = Offsets.new
    if args.size == 1 && args.first.is_a?(Hash)
      # Offset symbols are specified explicitly
      args.first.each do |key, value|
        Ref.extract_offset(value) # This is used for validation purposes
        offs[key] = value
      end
      raise 'all three offsets must be specified' unless offs.size == 3
      @xref, @yref, @zref = offs[:x], offs[:y], offs[:z]
    else
      # Offset symbols are to be extracted from the offsets themselves
      args.each do |arg|
        offset = Ref.extract_offset(arg)
        raise 'relative offset expected' unless offset.is_a?(Array)
        offs[offset.first] = offset.last
      end
      @xref = offs.include?(:x) ? Symbolic.collect(:x + offs[:x]) : :x
      @yref = offs.include?(:y) ? Symbolic.collect(:y + offs[:y]) : :y
      @zref = offs.include?(:z) ? Symbolic.collect(:z + offs[:z]) : :z
    end
  end

  def apply(obj)
    obj.ref(self)
  end

  def self.extract_offset(arg)
    # TODO more informative error messages
    ex = Symbolic.expand(Symbolic.coerce(arg))
    if ex.is_a?(Symbolic::Add)
      # :x+1
      coords = Set.new
      rest = []
      ex.args.each do |op|
        if CoordSymbols.include?(op)
          raise 'duplicate coordinate symbol found within offset expression' if coords.include?(op)
          coords << op
        else
          raise 'unexpected symbols found within offset expression' unless detect_symbols(op).empty?
          rest << op
        end
      end
      if coords.size == 0
        raise 'unexpected symbols found within offset expression' unless detect_symbols(ex).empty?
        ex # No offset symbols found - consider argument is an absolute coordinate reference
      elsif coords.size == 1
        [coords.to_a.first, Symbolic::Add.make(*rest)]
      else
        raise 'unsupported offset form'
      end
    else
      if CoordSymbols.include?(ex)
        [ex, 0]
      else
        raise 'unexpected symbols found within offset expression' unless detect_symbols(ex).empty?
        ex
      end
    end
  end

  def self.detect_symbols(obj)
    sc = SymbolCollector.new
    obj.apply(sc)
    sc.symbols
  end

end # Ref


#
class ExpressionCollector < Symbolic::Traverser
  attr_reader :instances
  def initialize(*exprs)
    @instances = Set.new
    exprs.each {|e| Symbolic.coerce(e).apply(self)}
  end
  def numeric(obj) end
  def field(obj)
    instances << obj
  end
  def scalar(obj)
    instances << obj
  end
end


#
class PrecedenceComputer < Symbolic::PrecedenceComputer
  def offset(obj) 100 end
  def field(obj) 100 end
  def scalar(obj) 100 end
  def ref(obj) 100 end
end # PrecedenceComputer


#
class Emitter < Symbolic::CEmitter
  def initialize(pc = PrecedenceComputer.new)
    super
  end
  def offset(obj) @out << obj.to_s end
  def field(obj) @out << obj.name.to_s end
  def scalar(obj) @out << obj.name.to_s end
  def ref(obj)
    embrace_arg = prec(obj.arg) < prec(obj)
    @out << '(' if embrace_arg
    obj.arg.apply(self)
    @out << ')' if embrace_arg
    @out << '('
    @out << [obj.xref, obj.yref, obj.zref].join(',')
    @out << '}'
  end
end # Emitter


end # Finita
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


#
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

  def hash
    name.hash ^ (type.hash<<1)
  end

  def ==(other)
    self.class == other.class && name == other.name && type == other.type
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

  def hash
    name.hash ^ (type.hash<<1) ^ (grid.hash<<2)
  end

  def ==(other)
    self.class == other.class && name == other.name && type == other.type && grid == other.grid
  end

  def apply(obj)
    obj.field(self)
  end

  def bind(gtor)
    grid.bind(gtor)
    Code.new(self, gtor)
  end

end # Field


#
class Traverser < Symbolic::Traverser

  def ref(obj)
    traverse_unary(obj)
  end

  def diff(obj)
    traverse_unary(obj)
  end

end # Traverser


#
class Applicator < Symbolic::Applicator

  def ref(obj)
    traverse_unary(obj)
  end

  def diff(obj)
    traverse_unary(obj)
  end

end # Applicator


#
class Index

  Coords = Set.new [:x, :y, :z]

  class Hash < ::Hash
    def []=(key, value)
      raise 'invalid index symbol' unless Index::Coords.include?(key)
      raise 'duplicate index symbol' if include?(key)
      super
    end
  end # Hash

  def self.extract(arg)
    # TODO more informative error messages
    ex = Symbolic.expand(Symbolic.coerce(arg))
    if ex.is_a?(Symbolic::Add)
      # :x+1
      coords = Set.new
      rest = []
      ex.args.each do |op|
        if Coords.include?(op)
          raise 'duplicate coordinate symbol found within index expression' if coords.include?(op)
          coords << op
        else
          raise 'unexpected symbols found within index expression' unless detect_symbols(op).empty?
          rest << op
        end
      end
      if coords.size == 0
        raise 'unexpected symbols found within index expression' unless detect_symbols(ex).empty?
        ex # No offset symbols found - consider argument is an absolute coordinate reference
      elsif coords.size == 1
        [coords.to_a.first, Symbolic::Add.make(*rest)]
      else
        raise 'invalid index form'
      end
    else
      if Coords.include?(ex)
        [ex, 0]
      else
        raise 'unexpected symbols found within index expression' unless detect_symbols(ex).empty?
        ex
      end
    end
  end

  def self.detect_symbols(obj)
    sc = SymbolCollector.new
    obj.apply(sc)
    sc.symbols
  end

  attr_reader :hash, :base, :delta, :index

  def initialize(arg)
    if arg.is_a?(Index)
      @base = arg.base
      @delta = arg.delta
      @index = arg.index
    else
      idx = Index.extract(arg)
      if idx.is_a?(Array)
        @base, @delta = idx
      else
        @base = idx
        @delta = nil
      end
      @index = Symbolic.simplify(arg)
    end
    @hash = @index.hash
  end

  def ==(other)
    self.class == other.class && base == other.base && delta == other.delta
  end

  def to_s
    @index.to_s
  end

  def absolute?
    @delta.nil?
  end

  def relative?
    not @delta.nil?
  end

  X = Index.new(:x)
  Y = Index.new(:y)
  Z = Index.new(:z)

end # Index


#
class Ref < Symbolic::UnaryFunction

  attr_reader :xindex, :yindex, :zindex

  def indices_hash
    {:x=>xindex, :y=>yindex, :z=>zindex}
  end

  def initialize(op, *args)
    super(op)
    ids = Index::Hash.new
    if args.size == 1 && args.first.is_a?(Hash)
      args.first.each do |k, v|
        ids[k] = Index.new(v) unless v.nil?
      end
    else
      args.each do |arg|
        idx = Index.new(arg)
        raise 'relative index expected' unless idx.relative?
        ids[idx.base] = idx
      end
    end
    @xindex = ids.include?(:x) ? ids[:x] : Index::X
    @yindex = ids.include?(:y) ? ids[:y] : Index::Y
    @zindex = ids.include?(:z) ? ids[:z] : Index::Z
  end

  def hash
    super ^ (xindex.hash<<1) ^ (yindex.hash<<2) ^ (zindex.hash<<3)
  end

  def ==(other)
    super && xindex == other.xindex && yindex == other.yindex && zindex == other.zindex
  end

  def apply(obj)
    obj.ref(self)
  end

  def new_instance(arg)
    self.class.new(arg, indices_hash)
  end

end # Ref


#
class Diff < Symbolic::UnaryFunction

  attr_reader :diffs

  def initialize(arg, diffs)
    super(arg)
    @diffs = diffs.is_a?(Hash) ? diffs : {diffs=>1}
  end

  def apply(obj)
    obj.diff(self)
  end

  def hash
    super ^ (diffs.hash<<1)
  end

  def ==(other)
    super && diffs == other.diffs
  end

  def new_instance(arg)
    self.class.new(arg, diffs)
  end

end # Diff


#
class Differ < Symbolic::Differ

  def scalar(obj)
    @result = zero? ? obj : 0
  end

  def field(obj)
    @result = zero? ? obj : Diff.new(obj, diffs)
  end

  def ref(obj)
    @result = Ref.new(apply(obj.arg), obj.indices_hash).convert
  end

  def diff(obj)
    @result = self.class.new(diffs_merge_with(obj.diffs)).apply(obj.arg).convert
  end

end # Differ


# Visitor class which performs partial (read incomplete) symbolic differentiation of expression.
class PartialDiffer < Differ

  # FIXME traversal interruption via throwing the exception is a kind of hack
  # Should find a more graceful way to do this

  class DetectException < Exception; end

  class DiffDetector < Traverser
    include Singleton
    def diff(obj)
      raise(DetectException)
    end
    def method_missing(*args) end
    def self.contains?(obj)
      begin
        obj.apply(self.instance)
      rescue DetectException
        true
      else
        false
      end
    end
  end # DiffDetector

  def apply(obj)
    if DiffDetector.contains?(obj)
      super
    else
      zero? ? obj : Diff.new(obj, diffs)
    end
  end

end # PartialDiffer


#
class RefMerger

  attr_reader :result

  def initialize(xindex = nil, yindex = nil, zindex = nil)
    @xindex = xindex
    @yindex = yindex
    @zindex = zindex
  end

  def indices_hash
    {:x=>@xindex, :y=>@yindex, :z=>@zindex}
  end

  def numeric(obj)
    @result = obj
  end

  def scalar(obj)
    @result = obj
  end

  def field(obj)
    @result = Ref.new(obj, indices_hash)
  end

  def ref(obj)
    ids = Index::Hash.new
    [[:x,obj.xindex,@xindex], [:y,obj.yindex,@yindex], [:z,obj.zindex,@zindex]].each do |base, obj_index, self_index|
      if self_index.nil?
        ids[base] = obj_index
      else
        raise 'both indices must be relative' unless obj_index.relative? && self_index.relative?
        raise 'bases do not coincide' unless base == obj_index.base && base == self_index.base
        ids[base] = Index.new(Symbolic.simplify(base + self_index.delta + obj_index.delta))
      end
    end
    merger = RefMerger.new(ids[:x], ids[:y], ids[:z])
    obj.arg.apply(merger)
    @result = merger.result
  end

  def add(obj)
    merge_nary(obj)
  end

  def multiply(obj)
    merge_nary(obj)
  end

  def exp(obj)
    merge_unary(obj)
  end

  def log(obj)
    merge_unary(obj)
  end

  def apply(obj)
    obj.apply(self)
    @result
  end

  private

  def merge_unary(obj)
    obj.arg.apply(self)
    @result = obj.class.new(@result)
  end

  def merge_nary(obj)
    ary = []
    obj.args.each do |arg|
      arg.apply(self)
      ary << @result
    end
    @result = obj.class.new(*ary)
  end

end # RefMerger


#
class SymbolCollector < Traverser

  attr_reader :symbols

  def initialize
    @symbols = Set.new
  end

  def symbol(obj)
    @symbols << obj
  end

  def method_missing(*args) end

end # SymbolCollector


#
class ExpressionCollector < Traverser

  attr_reader :expressions

  def initialize(*exprs)
    @expressions = Set.new
    exprs.each {|e| Symbolic.coerce(e).apply(self)}
  end

  def numeric(obj) end

  def field(obj)
    expressions << obj
  end

  def scalar(obj)
    expressions << obj
  end

end # ExpressionCollector


#
class PrecedenceComputer < Symbolic::PrecedenceComputer
  def field(obj) 100 end
  def scalar(obj) 100 end
  def ref(obj) 100 end
  def diff(obj) 100 end
end # PrecedenceComputer


#
class Emitter < Symbolic::CEmitter

  def initialize(pc = PrecedenceComputer.new)
    super
  end

  def field(obj) @out << obj.name end

  def scalar(obj) @out << obj.name end

  def ref(obj)
    embrace_arg = prec(obj.arg) < prec(obj)
    @out << '(' if embrace_arg
    obj.arg.apply(self)
    @out << ')' if embrace_arg
    @out << '('
    @out << [obj.xindex, obj.yindex, obj.zindex].join(',')
    @out << '}'
  end

  def diff(obj)
    @out << 'D'
    ary = []
    obj.diffs.each do |k,v|
      ary << (v > 1 ? "#{k}^#{v}" : k)
    end
    @out << "{#{ary.join(',')}}"
    @out << '('
    obj.arg.apply(self)
    @out << ')'
  end

end # Emitter


end # Finita
require 'singleton'
require 'code_builder'
require 'data_struct'


module Finita


VERSION = '0.1'


module Forwarder
  def set_forward_obj(obj)
    @forward_obj = obj
  end
  def method_missing(symbol, *args)
    @forward_obj.send(symbol, *args)
  end
end # Forwarder


class Range
  attr_reader :from, :to
  def initialize(*args)
    if args.size == 1
      from = Symbolic.coerce(0)
      to = Symbolic.simplify(Symbolic.coerce(args.first-1))
    elsif args.size == 2
      from = Symbolic.simplify(Symbolic.coerce(args.first))
      to = Symbolic.simplify(Symbolic.coerce(args.last))
    else
      raise(ArgumentError, 'invalid range specification')
    end
    @from, @to = from, to
  end
  def to_s
    "#{from}..#{to}"
  end
  def hash
    from.hash ^ (to.hash << 1)
  end
  def ==(other)
    equal?(other) || self.class == other.class && from == other.from && to == other.to
  end
  alias :eql? :==
  def sub
   unit? ? self : Range.new(from+1, to-1)
  end
  def sup
    Range.new(from-1, to+1) # TODO what about unit ranges?
  end
  def unit?
    from == to
  end
end # Range


class CodeTemplate
  def entities; [] end
  def priority
    if entities.empty?
      CodeBuilder::Priority::DEFAULT
    else
      min = entities.first.priority
      entities[1..-1].each {|e| p = e.priority; min = p if min > p}
      min-1
    end
  end
  def source_size
    stream = String.new
    write_defs(stream)
    stream.size
  end
  def attach(source) source << self if source.smallest? end
  def write_intf(stream) end
  def write_defs(stream) end
  def write_decls(stream) end
  # def ==()
  # alias :eql? :==
end # CodeTemplate


class StaticCodeTemplate < CodeTemplate
  include Singleton
end # StaticCodeTemplate


class BoundCodeTemplate < CodeTemplate
  attr_reader :gtor, :owner
  protected :owner
  def initialize(hash, gtor)
    @gtor = gtor
    tag, value = hash.flatten
    @owner = value
    define_singleton_method tag do
      value
    end
    gtor[value] = self
  end
  def hash
    self.class.hash ^ (gtor.hash << 1)
  end
  def ==(other)
    equal?(other) || self.class == other.class && owner == other.owner
  end
  alias :eql? :==
end # BoundCodeTemplate


class FunctionTemplate < CodeTemplate
  # def write_body(stream)
  attr_reader :name, :args, :result
  def initialize(name, args, result, visible)
    @name = name
    @args = args
    @result = result
    @visible = visible
  end
  def write_signature(stream)
    stream << "#{result} #{name}(#{args.join(',')})"
  end
  def write_intf(stream) write_intf_real(stream) if @visible end
  def write_decls(stream) write_intf_real(stream) unless @visible end
  def write_intf_real(stream)
    write_signature(stream)
    stream << ';'
  end
  def write_defs(stream)
    write_signature(stream)
    stream << '{'
    write_body(stream)
    stream << '}'
  end
end # FunctionTemplate


module AdapterMixin
  def assert; :FINITA_ASSERT end
  def malloc; :FINITA_MALLOC end
end # AdapterStubs


class ListAdapter < DataStruct::List
  include AdapterMixin
end # ListAdapter


class SetAdapter < DataStruct::Set
  include AdapterMixin
  def new_bucket_list
    ListAdapter.new("#{type}Bucket", element_type, comparator, visible)
  end
end # SetAdapter


class MapAdapter < DataStruct::Map
  include AdapterMixin
  def new_pair_set
    SetAdapter.new("#{type}PairSet", "#{type}Pair", "#{type}PairHash", "#{type}PairCompare", visible)
  end
end # MapAdapter


end # Finita
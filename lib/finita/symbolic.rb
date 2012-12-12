require 'symbolic'
require 'finita/common'
require 'finita/domain'


module Finita


class ::Numeric
  Precedence = [Integer, Float, Complex]
  def self.type_of(obj)
    if obj.is_a?(::Integer)
      Integer
    elsif obj.is_a?(::Numeric)
      obj.class
    else
      raise 'numeric value expected'
    end
  end
  def self.promoted_type(*types)
    type = types.first
    types[1..-1].each do |t|
      type = t if Precedence.index(t) > Precedence.index(type)
    end
    type
  end
end # Numeric


# Constant needs extra treatment
[::Fixnum, ::Float, ::Complex, ::Bignum, ::Rational].each do |cls|
  cls.class_eval do
    alias :finita_add +
    alias :finita_sub -
    alias :finita_mul *
    alias :finita_div /
    alias :finita_pow **
    def +(other) other.is_a?(Constant) ? self+other.value : finita_add(other) end
    def -(other) other.is_a?(Constant) ? self-other.value : finita_sub(other) end
    def *(other) other.is_a?(Constant) ? self*other.value : finita_mul(other) end
    def /(other) other.is_a?(Constant) ? self/other.value : finita_div(other) end
    def **(other) other.is_a?(Constant) ? self**other.value : finita_pow(other) end
    def[](*args) self end
  end
end


::Symbol.class_eval do
  def[](*args) self end
end


class Symbolic::Expression
  def [](*args)
    Ref.new(self, *args)
  end
  def to_s
    Emitter.new.emit!(self)
  end
end

class Collector < Symbolic::Traverser
  attr_reader :constants, :variables, :fields, :refs
  def initialize
    @constants = Set.new
    @variables = Set.new
    @fields = Set.new
    @refs = Set.new
  end
  def instances
    constants | variables | fields
  end
  def constant(obj)
    @constants << obj
  end
  def variable(obj)
    @variables << obj
  end
  def field(obj)
    @fields << obj
  end
  def ref(obj)
    @refs << obj
    obj.arg.apply(self)
    [obj.xindex.index, obj.yindex.index, obj.zindex.index].each {|e| e.apply(self)}
  end
  def numeric(obj) end
  def symbol(obj) end
  def apply!(*args)
    args.each {|e| Symbolic.coerce(e).apply(self)}
    self
  end
end # Collector


class Constant < Numeric
  attr_reader :name, :type, :value
  def initialize(name, value)
    @name = name.to_s
    @value = value
    @type = Numeric.type_of(value)
  end
  def hash
    value.hash
  end
  def ==(other)
    if other.is_a?(Numeric)
      value == other
    elsif other.is_a?(Constant)
      name == other.name && type == other.type
    else
      false
    end
  end
  alias :eql? :==
  def apply(obj)
    obj.constant(self)
  end
  def expand() self end
  def convert() self end
  def collect() self end
  def revert() self end
  def method_missing(method, *args)
    value.send(method, *args)
  end
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < CodeBuilder::Code
    class << self
      alias :__new__ :new
      def new(owner, problem_code)
        obj = __new__(owner, problem_code)
        problem_code << obj
      end
    end
    attr_reader :constant, :symbol
    def priority
      CodeBuilder::Priority::DEFAULT + 3
    end
    def initialize(constant, problem_code)
      @constant = constant
      @symbol = constant.name
      @problem_code = problem_code
      @problem_code.defines << :FINITA_COMPLEX if constant.type == Complex
    end
    def hash
      constant.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && constant == other.constant
    end
    def write_intf(stream)
      value = if constant.type == Complex
                "#{constant.value.real}+_Complex_I*(#{constant.value.imaginary})"
              else
                constant.value
              end
      stream << %$
      #define #{constant.name} #{@problem_code.problem.name}#{constant.name}
      static const #{NumericType[constant.type]} #{constant.name} = #{value};
    $
    end
  end # Code
end # Constant


class Variable < Symbolic::Expression
  attr_reader :name, :type
  def initialize(name, type)
    raise 'numeric type expected' unless NumericType.key?(type)
    @name = name.to_s
    @type = type
  end
  def hash
    name.hash ^ type.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && name == other.name && type == other.type
  end
  alias :eql? :==
  def apply(obj)
    obj.variable(self)
  end
  def expand() self end
  def convert() self end
  def collect() self end
  def revert() self end
  def[](*args) self end
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < CodeBuilder::Code
    class << self
      alias :__new__ :new
      def new(owner, problem_code)
        obj = __new__(owner, problem_code)
        problem_code << obj
      end
    end
    attr_reader :variable, :symbol
    def priority
      CodeBuilder::Priority::DEFAULT + 2
    end
    def initialize(variable, problem_code)
      @variable = variable
      @symbol = variable.name
      @problem_code = problem_code
      @problem_code.defines << :FINITA_COMPLEX if variable.type == Complex
    end
    def hash
      variable.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && variable == other.variable
    end
    def write_intf(stream)
      stream << %$
      #define #{variable.name} #{@problem_code.type}#{variable.name}
      extern #{NumericType[variable.type]} #{variable.name};
    $
    end
    def write_defs(stream)
      stream << %$
      #{NumericType[variable.type]} #{variable.name};
    $
    end
  end # Code
end # Variable


class Field < Symbolic::Expression
  attr_reader :name, :type, :domain
  def initialize(name, type, domain)
    raise 'numeric type expected' unless NumericType.key?(type)
    @name = name.to_s # TODO validate
    @type = type # TODO validate
    @domain = domain
  end
  def hash
    name.hash ^ domain.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && name == other.name && type == other.type && domain == other.domain
  end
  alias :eql? :==
  def apply(obj)
    obj.field(self)
  end
  def expand() self end
  def convert() self end
  def collect() self end
  def revert() self end
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < DataStruct::Code
    class << self
      alias :__new__ :new
      def new(owner, problem_code)
        obj = __new__(owner, problem_code)
        problem_code << obj
      end
    end
    def entities; super + [@domain_code] end
    attr_reader :field, :symbol, :instance
    def initialize(field, problem_code)
      @field = field
      super("#{problem_code.problem.name}Field#{field.name}")
      @instance = type
      @symbol = field.name
      @domain_code = field.domain.code(problem_code)
      @ctype = Finita::NumericType[field.type]
      problem_code.initializers << self
      problem_code.defines << :FINITA_COMPLEX if field.type == Complex
    end
    def hash
      field.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && field == other.field
    end
    def write_intf(stream)
      stream << %$
        #define #{field.name}(x,y,z) (#{instance}.data[#{@domain_code.index}(#{instance}.area, x, y, z)])
        struct #{type} {
          #{@ctype}* data;
          #{@domain_code.type}* area;
        };
        extern struct #{type} #{instance};
      $
    end
    def write_defs(stream)
      stream << %$
        struct #{type} #{instance};
      $
    end
    def write_initializer(stream)
      stream << %${
        #{instance}.area = &#{@domain_code.instance};
        #{instance}.data = (#{@ctype}*)#{calloc}(#{@domain_code.size}(#{instance}.area), sizeof(#{@ctype})); #{assert}(#{instance}.data);
      }$
    end
  end # Code
end # Field


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
    ex = Finita.expand(arg)
    if ex.is_a?(Symbolic::Add)
      # :x+1
      coords = Set.new
      rest = []
      ex.args.each do |op|
        if Coords.include?(op)
          raise 'duplicate coordinate symbol found within index expression' if coords.include?(op)
          coords << op
        else
          raise 'unexpected symbols found within index expression' unless Symbol::Collector.new.apply!(op).empty?
          rest << op
        end
      end
      if coords.size == 0
        raise 'unexpected symbols found within index expression' unless Symbol::Collector.new.apply!(ex).empty?
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
        raise 'unexpected symbols found within index expression' unless Symbol::Collector.new.apply!(ex).empty?
        ex
      end
    end
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
      @index = Finita.simplify(arg)
    end
    @hash = @index.hash
  end
  def ==(other)
    equal?(other) || self.class == other.class && base == other.base && delta == other.delta
  end
  alias :eql? :==
  def to_s
    CEmitter.new.emit!(index)
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


class Ref < Symbolic::UnaryFunction
  attr_reader :xindex, :yindex, :zindex
  def initialize(op, *args)
    super(op)
    if args.size == 1 && args.first.is_a?(Array)
      @xindex, @yindex, @zindex = args.first
    else
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
  end
  def hash
    super ^ (xindex.hash << 1) ^ (yindex.hash << 2) ^ (zindex.hash << 3)
  end
  def ==(other)
    super && xindex == other.xindex && yindex == other.yindex && zindex == other.zindex
  end
  alias :eql? :==
  def apply(obj)
    obj.ref(self)
  end
  def new_instance(arg)
    self.class.new(arg, [xindex, yindex, zindex])
  end
end # Ref


class Ref::Merger
  attr_reader :result
  def initialize(xindex = nil, yindex = nil, zindex = nil)
    @xindex = xindex
    @yindex = yindex
    @zindex = zindex
  end
  def numeric(obj)
    @result = obj
  end
  alias :constant :numeric
  def variable(obj)
    @result = obj
  end
  def field(obj)
    @result = Ref.new(obj, {:x=>@xindex, :y=>@yindex, :z=>@zindex})
  end
  def ref(obj)
    ids = Index::Hash.new
    [[:x,obj.xindex,@xindex], [:y,obj.yindex,@yindex], [:z,obj.zindex,@zindex]].each do |base, obj_index, self_index|
      if self_index.nil?
        ids[base] = obj_index
      else
        raise 'both indices must be relative' unless obj_index.relative? && self_index.relative?
        raise 'bases do not coincide' unless base == obj_index.base && base == self_index.base
        ids[base] = Index.new(Finita.simplify(base + self_index.delta + obj_index.delta))
      end
    end
    merger = self.class.new(ids[:x], ids[:y], ids[:z])
    obj.arg.apply(merger)
    @result = merger.result
  end
  def add(obj)
    merge_nary(obj)
  end
  def multiply(obj)
    merge_nary(obj)
  end
  def power(obj)
    merge_nary(obj)
  end
  def exp(obj)
    merge_unary(obj)
  end
  def log(obj)
    merge_unary(obj)
  end
  def apply!(obj)
    obj.convert.apply(self)
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
end # Ref::Merger


class Symbol::Collector < Symbolic::Traverser
  attr_reader :symbols
  def initialize
    @symbols = Set.new
  end
  def symbol(obj)
    @symbols << obj
  end
  def apply!(obj)
    obj.apply(self)
    symbols
  end
  def method_missing(*args) end
end # Symbol::Collector


class Ref::Collector < Symbolic::Traverser
  attr_reader :refs
  def initialize(fields)
    @fields = fields
    @refs = Set.new
  end
  def ref(obj)
    raise 'unexpected reference operand' unless obj.arg.is_a?(Field)
    @refs << obj if @fields.include?(obj.arg)
  end
  def apply!(obj)
    obj.apply(self)
    refs
  end
  def method_missing(*args) end
end # Ref::Collector


class TypeInferer < Symbolic::Traverser
  def apply!(obj)
    obj.apply(self)
    @type
  end
  def numeric(obj)
    @type = Numeric.type_of(obj)
  end
  def constant(obj)
    @type = obj.type
  end
  def variable(obj)
    @type = obj.type
  end
  def field(obj)
    @type = obj.type
  end
  def ref(obj)
    obj.arg.apply(self)
  end
  def exp(obj)
    super
    @type = Float if @type.equal?(Integer)
  end
  def log(obj)
    super
    @type = Float if @type.equal?(Integer)
  end
  protected
  def traverse_nary(obj)
    @type = Numeric.promoted_type(*obj.args.collect {|o| o.apply(self); @type})
  end
end #


class ObjectCollector < Symbolic::Traverser
  attr_reader :objects
  def initialize(*classes)
    @classes = classes
    @objects = Set.new
  end
  def apply!(obj)
    obj.apply(self)
    @objects
  end
  def collect_obj(obj)
    @classes.each do |c|
      if obj.is_a?(c)
        @objects << obj
        break
      end
    end
  end
  alias :numeric :collect_obj
  alias :constant :collect_obj
  alias :variable :collect_obj
  alias :field :collect_obj
  def ref(obj)
    traverse_unary(obj)
  end
  protected
  def traverse_unary(obj)
    collect_obj(obj)
    super
  end
  def traverse_nary(obj)
    collect_obj(obj)
    super
  end
end # ObjectCollector


# tries to convert given expression info a product term*rest and returns rest or nil
class ProductExtractor
  def apply!(obj, term)
    @term = term
    Symbolic.expand(obj).apply(self)
    @rest
  end
  def compare_obj(obj) @rest = (obj == @term ? 1 : nil) end
  alias :numeric :compare_obj
  alias :constant :compare_obj
  alias :variable :compare_obj
  alias :field :compare_obj
  alias :ref :compare_obj
  alias :add :compare_obj
  alias :exp :compare_obj
  alias :ln :compare_obj
  def multiply(obj)
    index = obj.args.index(@term)
    if index.nil?
      @rest = nil
    else
      args = obj.args.dup; args.slice!(index)
      @rest = Multiply.make(*args)
    end
  end
end # TermExtractor


class PrecedenceComputer < Symbolic::PrecedenceComputer
  def constant(obj) 100 end
  def variable(obj) 100 end
  def field(obj) 100 end
  def ref(obj) 100 end
end # PrecedenceComputer


class Emitter < Symbolic::Emitter
  def initialize(pc = PrecedenceComputer.new)
    super
  end
  def constant(obj)
    @out << obj.name
  end
  def variable(obj)
    @out << obj.name
  end
  def field(obj)
    @out << obj.name
  end
  def ref(obj)
    embrace_arg = prec(obj.arg) < prec(obj)
    @out << '(' if embrace_arg
    obj.arg.apply(self)
    @out << ')' if embrace_arg
    @out << '('
    @out << [obj.xindex, obj.yindex, obj.zindex].join(',')
    @out << ')'
  end
end # Emitter


class CEmitter < Symbolic::CEmitter
  def initialize(pc = PrecedenceComputer.new)
    super
  end
  def constant(obj)
    @out << obj.name
  end
  def variable(obj)
    @out << obj.name
  end
  def field(obj)
    @out << obj.name
  end
  def ref(obj)
    embrace_arg = prec(obj.arg) < prec(obj)
    @out << '(' if embrace_arg
    obj.arg.apply(self)
    @out << ')' if embrace_arg
    @out << '('
    @out << [obj.xindex, obj.yindex, obj.zindex].join(',')
    @out << ')'
  end
  def exp(obj)
    unary_func(TypeInferer.new.apply!(obj).equal?(Complex) ? 'cexp' : 'exp', obj)
  end
  def log(obj)
    unary_func(TypeInferer.new.apply!(obj).equal?(Complex) ? 'clog' : 'log', obj)
  end
  def power(obj)
    power_op(obj, *obj.args)
  end
  private
  def power_op(obj, *ops)
    pow = TypeInferer.new.apply!(obj).equal?(Complex) ? 'cpow' : 'pow'
    if ops.size > 1
      @out << pow << '('
      power_op(obj, *ops[0..-2])
      @out <<','
      ops.last.apply(self)
      @out << ')'
    else
      ops.last.apply(self)
    end
  end
end # CEmitter


end # Finita
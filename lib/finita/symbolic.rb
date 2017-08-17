require "set"
require "symbolic"
require "finita/common"
require "finita/domain"


module Finita


class ::Numeric
  Precedence = [Integer, Float, Complex]
  def self.type_of(obj)
    if obj.is_a?(::Integer)
      Integer
    elsif obj.is_a?(::Numeric)
      obj.class
    else
      raise "numeric value expected"
    end
  end
  def self.promoted_type(*types)
    if types.empty?
      Integer
    else
      type = types.first
      types[1..-1].each do |t|
        type = t if Precedence.index(t) > Precedence.index(type)
      end
      type
    end
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
  attr_reader :constants, :variables, :fields, :refs, :udfs
  def initialize
    @constants = Set.new
    @variables = Set.new
    @fields = Set.new
    @udfs = Set.new
    @refs = Set.new
  end
  def instances
    constants | variables | fields | udfs
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
  def udf(obj)
    @udfs << obj
  end
  def ref(obj)
    @refs << obj
    apply!(obj.arg)
    [obj.xindex.index, obj.yindex.index, obj.zindex.index].each {|e| apply!(e)}
  end
  def d(obj)
    apply!(obj.arg)
  end
  def numeric(obj) end
  def symbol(obj) end
  def apply!(*args)
    args.each {|e| Symbolic.coerce(e).apply(self)}
    self
  end
end # Collector


class Constant < Numeric
  Symbolic.freezing_new(self)
  attr_reader :hash, :name, :type, :value
  def initialize(name, value)
    @name = name.to_s
    @value = value
    @type = Numeric.type_of(value)
    @hash = value.hash # TODO
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
  include Symbolic::TrivialOperations
  def method_missing(method, *args)
    value.send(method, *args)
  end
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < Finita::Code
    class << self
      alias :default_new :new
      def new(owner, problem_code)
        problem_code.bind!(owner) {default_new(owner, problem_code)}
      end
    end
    attr_reader :constant, :symbol
    def entities
      super.concat((@constant.type == Complex) ? [Finita::ComplexCode] : [])
    end
    def initialize(constant, problem_code)
      @constant = constant
      @symbol = constant.name
      @problem_code = problem_code
    end
    def hash
      constant.hash
    end
    def ==(other)
      equal?(other) || self.class == other.class && constant == other.constant
    end
    alias :eql? :==
    def write_intf(stream)
      value = constant.type == Complex ? "#{constant.value.real}+_Complex_I*(#{constant.value.imaginary})" : constant.value
      stream << %$
        #define #{constant.name} #{@problem_code.problem.name}#{constant.name}
        #{static} const #{CType[constant.type]} #{constant.name} = #{value};
      $
    end
  end # Code
end # Constant


class Variable < Symbolic::Expression
  attr_reader :hash, :name, :type
  def initialize(name, type)
    raise "numeric type expected" unless CType.key?(type)
    @name = name.to_s
    @type = type
    @hash = self.class.hash ^ name.hash ^ type.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && name == other.name && type == other.type
  end
  alias :eql? :==
  def apply(obj)
    obj.variable(self)
  end
  include Symbolic::TrivialOperations
  def[](*args) self end
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < Finita::Code
    class << self
      alias :default_new :new
      def new(owner, problem_code)
        problem_code.bind!(owner) {default_new(owner, problem_code)}
      end
    end
    attr_reader :variable, :symbol
    def entities
      super.concat((@variable.type == Complex) ? [Finita::ComplexCode] : [])
    end
    def initialize(variable, problem_code)
      @variable = variable
      @symbol = variable.name
      @problem_code = problem_code
    end
    def hash
      variable.hash
    end
    def ==(other)
      equal?(other) || self.class == other.class && variable == other.variable
    end
    alias :eql? :==
    def write_intf(stream)
      stream << %$
        #define #{variable.name} #{@problem_code.type}#{variable.name}
        #{extern} #{CType[variable.type]} #{variable.name};
      $
    end
    def write_defs(stream)
      stream << %$#{CType[variable.type]} #{variable.name};$
    end
  end # Code
end # Variable


class Field < Symbolic::Expression
  # FIXME : this is a kind of hack needed by the ViennaCL backend to prevent function-like macro name clash with the ViennaCL's template type names.
  @@defined_fields = Set.new
  def self.defined_fields
    @@defined_fields
  end
  attr_reader :hash, :name, :type, :domain
  def initialize(name, type, domain)
    raise "numeric type expected" unless CType.key?(type)
    @@defined_fields << @name = name.to_s # TODO validate
    @type = type # TODO validate
    @domain = domain
    @hash =  self.class.hash ^ name.hash ^ domain.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && name == other.name && type == other.type && domain == other.domain
  end
  alias :eql? :==
  def apply(obj)
    obj.field(self)
  end
  include Symbolic::TrivialOperations
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < Finita::Code
    class << self
      alias :default_new :new
      def new(owner, problem_code)
        problem_code.bind!(owner) {default_new(owner, problem_code)}
      end
    end
    attr_reader :field, :instance
    def entities
      super.concat((@field.type == Complex) ? [Finita::ComplexCode, @domain_code] : [@domain_code]) << XYZCode << StringCode
    end
    def initialize(field, problem_code)
      @field = field
      super("#{problem_code.type}#{field.name}")
      @instance = type
      @xyz = "#{field.name}_XYZ"
      @ctype = Finita::CType[field.type]
      @domain_code = field.domain.code(problem_code)
      problem_code.initializer_codes << self
    end
    def hash
      field.hash
    end
    def ==(other)
      equal?(other) || self.class == other.class && field == other.field
    end
    alias :eql? :==
    def write_intf(stream)
      stream << %$
        #{extern} #{@ctype}* #{instance};
        #ifndef NDEBUG
          #define #{field.name}(x,y,z) (*#{ref}(x, y, z))
          #{extern} #{@ctype}* #{ref}(int, int, int);
        #else
          #define #{field.name}(x,y,z) (#{instance}[#{@domain_code.index}(&#{@domain_code.instance}, x, y, z)])
        #endif
      $
      if @domain_code.named?
        stream << %$
          #define #{@xyz} #{@domain_code.xyz}
        $
      else
        stream << %$
          #define #{@xyz} #{instance}XYZ
          #{extern} #{XYZCode.type} #{@xyz};
        $
      end
    end
    def write_defs(stream)
      stream << %$
        #{@ctype}* #{instance};
        #ifndef NDEBUG
          #{@ctype}* #{ref}(int x, int y, int z) {
            FINITA_ENTER
            if(!#{@domain_code.within}(&#{@domain_code.instance}, x, y, z)) {
              #{StringCode.type} out;
              #{StringCode.ctor}(&out, NULL);
              #{StringCode.pushFormat}(&out, "#{field.name}(%d,%d,%d) is not within ", x, y, z);
              #{@domain_code.info}(&#{@domain_code.instance}, &out);
              FINITA_FAILURE(#{StringCode.chars}(&out));
            }
            FINITA_RETURN(&#{instance}[#{@domain_code.index}(&#{@domain_code.instance}, x, y, z)]);
          }
        #endif
      $
      stream << %$#{XYZCode.type} #{@xyz};$ unless @domain_code.named?
    end
    def write_initializer(stream)
      stream << %$#{instance} = (#{@ctype}*)#{calloc}(#{@domain_code.size}(&#{@domain_code.instance}), sizeof(#{@ctype})); #{assert}(#{instance});$
      stream << %${
        #{@domain_code.it} it;
        size_t index = 0;
        #{XYZCode.ctor}(&#{@xyz}, #{@domain_code.size}(&#{@domain_code.instance}));
        #{@domain_code.itCtor}(&it, &#{@domain_code.instance});
        while(#{@domain_code.itMove}(&it)) {
          #{@domain_code.node} node = #{@domain_code.itGet}(&it);
          #{XYZCode.set}(&#{@xyz}, index++, node.x, node.y, node.z);
        }
      }$ unless @domain_code.named?
    end
  end # Code
end # Field


class UDF < Symbolic::Expression
  attr_reader :hash, :name, :type
  def initialize(name, type)
    @name = name.to_s # TODO validate
    @type = type # TODO validate
    @hash =  self.class.hash ^ name.hash ^ type.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && name == other.name && type == other.type
  end
  alias :eql? :==
  def apply(obj)
    obj.udf(self)
  end
  include Symbolic::TrivialOperations
  def code(problem_code)
    Code.new(self)
  end
  class Code < Finita::Code
    attr_reader :udf
    def initialize(udf)
      @udf = udf
      super("UDF#{udf.name}")
    end
    def hash
      udf.hash
    end
    def ==(other)
      equal?(other) || self.class == other.class && udf == other.udf
    end
    alias :eql? :==
    def write_intf(stream)
      stream << %$
        #{extern} #{Finita::CType[udf.type]} #{udf.name}(int, int, int);
      $
    end
  end # Code
end # UDF


class Index
  Symbolic.freezing_new(self)
  Coords = Set[:x, :y, :z]
  class Hash < ::Hash
    def []=(key, value)
      raise "invalid index symbol" unless Index::Coords.include?(key)
      raise "duplicate index symbol" if include?(key)
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
          raise "duplicate coordinate symbol found within index expression" if coords.include?(op)
          coords << op
        else
          raise "unexpected symbols found within index expression" unless Symbol::Collector.new.apply!(op).empty?
          rest << op
        end
      end
      if coords.size == 0
        raise "unexpected symbols found within index expression" unless Symbol::Collector.new.apply!(ex).empty?
        ex # No offset symbols found - consider argument is an absolute coordinate reference
      elsif coords.size == 1
        [coords.to_a.first, Symbolic::Add.make(*rest)]
      else
        raise "invalid index form"
      end
    else
      if Coords.include?(ex)
        [ex, 0]
      else
        raise "unexpected symbols found within index expression" unless Symbol::Collector.new.apply!(ex).empty?
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
    @hash = self.class.hash ^ index.hash # TODO
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


class D < Symbolic::UnaryFunction
  Diffs = Set[:x, :y, :z]
  attr_reader :diffs
  def initialize(op, arg)
    super(op)
    @diffs = Symbolic::Differ.coerce(arg)
    @hash ^= diffs.hash # TODO
  end
  def ==(other)
    super && diffs == other.diffs
  end
  alias :eql? :==
  def apply(obj)
    obj.d(self)
  end
  def new_instance(arg)
    self.class.new(arg, diffs)
  end
end # D


class Differ < Symbolic::Differ
  def constant(obj)
    @result = zero? ? obj : 0
  end
  def variable(obj)
    @result = zero? ? obj : 0
  end
  def field(obj)
    @result = zero? ? obj : D.new(obj, diffs)
  end
  def udf(obj)
    @result = zero? ? obj : D.new(obj, diffs)
  end
  def ref(obj)
    @result = Ref.new(apply!(obj.arg), obj.xindex, obj.yindex, obj.zindex)
  end
  def d(obj)
    @result = self.class.new(merge_diffs(obj)).apply!(obj.arg)
  end
  protected
  def merge_diffs(diff_obj)
    merged_diffs = {}; merged_diffs.default = 0
    [diffs, diff_obj.diffs].each do |ds|
      ds.each do |k,v|
        merged_diffs[k] += v
      end
    end
    merged_diffs
  end
  def new_diff(obj)
    zero? ? obj : D.new(obj, diffs)
  end
end # Differ


class IncompleteDiffer < Differ
  def apply!(obj)
    ObjectCollector.new(D).apply!(obj).empty? ? new_diff(obj) : super
  end
end # IncompleteDiffer


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
          raise "relative index expected" unless idx.relative?
          ids[idx.base] = idx
        end
      end
      @xindex = ids.include?(:x) ? ids[:x] : Index::X
      @yindex = ids.include?(:y) ? ids[:y] : Index::Y
      @zindex = ids.include?(:z) ? ids[:z] : Index::Z
    end
    @hash ^= (xindex.hash << 1) ^ (yindex.hash << 2) ^ (zindex.hash << 3) # TODO
  end
  def xyz?
    xindex == Index::X && yindex == Index::Y && zindex == Index::Z
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
  def udf(obj)
    @result = Ref.new(obj, {:x=>@xindex, :y=>@yindex, :z=>@zindex})
  end
  def ref(obj)
    ids = Index::Hash.new
    [[:x,obj.xindex,@xindex], [:y,obj.yindex,@yindex], [:z,obj.zindex,@zindex]].each do |base, obj_index, self_index|
      if self_index.nil?
        ids[base] = obj_index
      else
        raise "both indices must be relative" unless obj_index.relative? && self_index.relative?
        raise "bases do not coincide" unless base == obj_index.base && base == self_index.base
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
    obj.convert!.apply(self)
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
    raise "unexpected reference operand" unless obj.arg.is_a?(Field)
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
  def udf(obj)
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
  def numeric(obj) collect_obj(obj) end
  def constant(obj) collect_obj(obj) end
  def variable(obj) collect_obj(obj) end
  def field(obj) collect_obj(obj) end
  def udf(obj) collect_obj(obj) end
  def ref(obj) traverse_unary(obj) end
  def d(obj) traverse_unary(obj) end
  protected
  def collect_obj(obj)
    @classes.each do |c|
      if obj.is_a?(c)
        @objects << obj
        break
      end
    end
  end
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
  alias :udf :compare_obj
  alias :ref :compare_obj
  alias :add :compare_obj
  alias :exp :compare_obj
  alias :ln :compare_obj
  def multiply(obj)
    index = obj.args.index(@term)
    if index.nil?
      @rest = nil
    else
      args = obj.args.dup
      args.slice!(index)
      @rest = Symbolic::Multiply.make(*args)
    end
  end
end # TermExtractor


class PrecedenceComputer < Symbolic::PrecedenceComputer
  def constant(obj) 100 end
  def variable(obj) 100 end
  def field(obj) 100 end
  def udf(obj) 100 end
  def ref(obj) 100 end
  def d(obj) 100 end
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
  def udf(obj)
    @out << obj.name
  end
  def ref(obj)
    embrace = prec(obj.arg) < prec(obj)
    @out << "(" if embrace
    obj.arg.apply(self)
    @out << ")" if embrace
    @out << "["
    @out << [obj.xindex, obj.yindex, obj.zindex].join(",")
    @out << "]"
  end
  def d(obj)
    @out << "D{" << obj.diffs.collect {|v,d| d == 1 ? v : "#{v}^#{d}"}.join(",") << "}("
    obj.arg.apply(self)
    @out << ")"
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
  def udf(obj)
    @out << obj.name
  end
  def ref(obj)
    embrace = prec(obj.arg) < prec(obj)
    @out << "(" if embrace
    obj.arg.apply(self)
    @out << ")" if embrace
    @out << "("
    @out << [obj.xindex, obj.yindex, obj.zindex].join(",")
    @out << ")"
  end
  def exp(obj)
    unary_func(TypeInferer.new.apply!(obj).equal?(Complex) ? "cexp" : "exp", obj)
  end
  def log(obj)
    unary_func(TypeInferer.new.apply!(obj).equal?(Complex) ? "clog" : "log", obj)
  end
  def power(obj)
    power_op(obj, *obj.args)
  end
  private
  def power_op(obj, *ops)
    pow = TypeInferer.new.apply!(obj).equal?(Complex) ? "cpow" : "pow"
    if ops.size > 1
      @out << pow << "("
      power_op(obj, *ops[0..-2])
      @out << ","
      ops.last.apply(self)
      @out << ")"
    else
      ops.last.apply(self)
    end
  end
end # CEmitter


end # Finita
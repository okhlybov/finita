require 'symbolic'
require 'finita/common'
require 'finita/domain'


module Finita


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
  end
end


class Collector < Symbolic::Traverser
  attr_reader :constants, :variables, :fields
  def self.collect(*exprs)
    collector = Collector.new
    exprs.each {|e| Symbolic.coerce(e).apply(collector)}
    collector
  end
  def initialize
    @constants = Set.new
    @variables = Set.new
    @fields = Set.new
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
  def numeric(*args) end
end # Collector


class Constant < Numeric
  attr_reader :name, :type, :value
  def initialize(name, value)
    @name = name.to_s
    @value = value
    @type = if value.is_a?(Integer)
              Integer
            elsif value.is_a?(Numeric)
              value.class
            else
              raise 'numeric value expected'
            end
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
  def apply(obj)
    obj.variable(self)
  end
  def expand() self end
  def convert() self end
  def collect() self end
  def revert() self end
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
  def apply(obj)
    obj.field(self)
  end
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
      super("#{problem_code.problem.name}#{field.name}")
      @instance = type
      @symbol = field.name
      @domain_code = field.domain.code(problem_code)
      @ctype = Finita::NumericType[field.type]
      problem_code.initializers << self
      problem_code.defines << :FINITA_COMPLEX if field.type == Complex
    end
    def hash
      @field.hash
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




class PrecedenceComputer < Symbolic::PrecedenceComputer
  def constant(obj) 100 end
  def variable(obj) 100 end
  def field(obj) 100 end
end # PrecedenceComputer


class CEmitter < Symbolic::CEmitter
  def self.emit(e)
    emitter = CEmitter.new
    e.apply(emitter)
    emitter.to_s
  end
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
    @out << obj.name << '(x,y,z)'
  end
end # CEmitter


end # Finita
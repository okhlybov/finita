# Module for manipulating the symbolic expressions.
#
# Note: alters the following standard Ruby classes: ::Symbol, ::Numeric, ::Fixnum, ::Bignum, ::Float, ::Complex, ::Rational.
module Symbolic


# Standard mathematics functions.
module Math
  def self.exp(obj) Symbolic::Exp.new(obj) end
  def self.log(obj) Symbolic::Log.new(obj) end
end


# Converts obj to symbolic expression node.
#
# If obj is already an Expression instance, passes it through.
#
# Raises TypeError exception if no conversion is possible.
def self.coerce(obj)
  if obj.is_a?(Expression)
    obj
  elsif obj.is_a?(Numeric)
    obj
  elsif obj.is_a?(Symbol)
    obj
  else
    raise(TypeError, "#{obj}:#{obj.class} can't be coerced into Symbolic::Expression")
  end
end


#
def self.simplify(obj)
  obj = obj.convert
  obj = expand(obj)
  obj = collect(obj)
  obj = obj.revert
end


#
def self.expand(obj)
  obj_ = nil
  until obj == obj_
    obj_ = obj
    obj = obj.convert.expand
  end
  obj
end


#
def self.collect(obj)
  obj_ = nil
  until obj == obj_
    obj_ = obj
    obj = obj.collect.convert
  end
  obj
end


# Returns a copy of array args with the _first_ occurrence of obj removed or nil if no obj was encountered.
def self.split_args(args, obj)
  found = false
  out = args.select do |op|
    if !found && op == obj
      found = true
      false
    else
      true
    end
  end
  found ? out : nil
end


#$objs = {}
# Instructs the constructor to freeze the object after creation.
def self.freezing_new(cls)
  class << cls
    alias :freezing_new :new
    def new(*args)
      obj = freezing_new(*args)
      obj.freeze
      #hash = obj.hash
      #if $objs.include?(hash)
      #  $objs[hash] << obj
      #else
      #  $objs[hash] = Set.new [obj]
      #end
      obj
    end
  end
end


# Predefined operators.
module Operators
  def +@() Symbolic::Plus.new(self) end
  def -@() Symbolic::Minus.new(self) end
  def +(other) Symbolic::Add.new(self, other) end
  def -(other) Symbolic::Subtract.new(self, other) end
  def *(other) Symbolic::Multiply.new(self, other) end
  def /(other) Symbolic::Divide.new(self, other) end
  def **(other) Symbolic::Power.new(self, other) end
end


# Mathematical symbol.
#
# This is a standard Ruby class modified to mimic the Symbolic::Expression descendant behavior.
class ::Symbol
  include Operators
  def apply(obj) obj.symbol(self) end
  def expand() self end
  def convert() self end
  def collect() self end
  def revert() self end
end


# Numeric constant.
#
# This is a standard Ruby class modified to mimic the Symbolic::Expression descendant behavior.
class ::Numeric
  def apply(obj) obj.numeric(self) end
  def expand() self end
  def convert() self end
  def collect() self end
  def revert() self end
  def extract_minus_one
    if self == -1
      1
    elsif self < 0
      abs
    else
      nil
    end
  end
end


class ::Complex
  def extract_minus_one
    if real == -1
      Complex(1, -imag)
    elsif real < 0
      Complex(real.abs, -imag)
    else
      nil
    end
  end
end


#
[::Fixnum, ::Float, ::Complex, ::Bignum, ::Rational].each do |cls|
  cls.class_eval do
    alias :symbolic_add +
    alias :symbolic_sub -
    alias :symbolic_mul *
    alias :symbolic_div /
    alias :symbolic_pow **
    def +(other) other.is_a?(Numeric) ? symbolic_add(other) : Add.new(self, other) end
    def -(other) other.is_a?(Numeric) ? symbolic_sub(other) : Subtract.new(self, other) end
    def *(other) other.is_a?(Numeric) ? symbolic_mul(other) : Multiply.new(self, other) end
    def /(other) other.is_a?(Numeric) ? symbolic_div(other) : Divide.new(self, other) end
    def **(other) other.is_a?(Numeric) ? symbolic_pow(other) : Power.new(self, other) end
  end
end


# Base class for symbolic expressions.
#
# Standard Ruby classes (::Symbol, ::Numeric and their descendants) which are not part
# of the Expression hierarchy but nonetheless considered valid expressions are
# modified accordingly to mimic Expression behavior.
class Expression
  # Enforces the immutability of all user-defined expression descendants.
  Symbolic.freezing_new(self)
  # Returns string representation of self. Employs Emitter class for string rendering.
  def to_s
    Emitter.new.emit!(self)
  end
  # Performs object comparison.
  # def ==(other)
  # Every Expression descendant must redefine this method.
  # Employs Expression#== for object comparison.
  # The code within the Symbolic package assumes the equivalency of #eql? and #== methods and
  # the subclasses of the Expression class redefine the latter to provide object comparison, therefore
  # this definition must be left as is otherwise things might break.
  # Each redefinition of #== should be followed by the corresponding alias :eql? :==
  include Operators
end


# Base class for functions of one argument.
class UnaryFunction < Expression
  attr_reader :arg, :hash
  def initialize(arg)
    @arg = Symbolic.coerce(arg)
    @hash = arg.hash ^ self.class.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && arg == other.arg
  end
  alias :eql? :==
  def convert
    new_instance(arg.convert)
  end
  def revert
    new_instance(arg.revert)
  end
  def expand
    new_instance(arg.expand)
  end
  def collect
    new_instance(arg.collect)
  end
  def new_instance(arg)
    # to be overriden in descendant classes which require additional arguments
    # to be passed to the respective constructors
    self.class.new(arg)
  end
end


# Base class for functions of two or more arguments.
class NaryFunction < Expression
  attr_reader :args, :contents, :hash
  def initialize(*args)
    @args = args.collect {|obj| Symbolic.coerce(obj)}
    @contents = Hash.new; contents.default = 0
    args.each {|arg| contents[arg] += 1}
    @hash = contents.hash ^ self.class.hash # TODO
  end
  def convert
    new_instance(*args.collect{|arg| arg.convert})
  end
  def revert
    new_instance(*args.collect{|arg| arg.convert})
  end
  def expand
    new_instance(*args.collect{|arg| arg.expand})
  end
  def collect
    new_instance(*args.collect{|arg| arg.collect})
  end
  def new_instance(*args)
    self.class.new(*args)
  end
end


# Symbolic unary plus.
class Plus < UnaryFunction
  def apply(obj) obj.plus(self) end
  def convert
    arg.convert # +x --> x
  end
end


# Symbolic unary minus.
class Minus < UnaryFunction
  def apply(obj) obj.minus(self) end
  def convert
    (-1)*arg.convert # -x --> (-1)*x
  end
  def extract_minus_one
    arg
  end
end


# Mixin for commutative N-ary functions.
module Commutative
  def ==(other)
    equal?(other) || self.class == other.class && contents == other.contents
  end
  alias :eql? :==
end


# Mixin for non-commutative N-ary functions.
module Noncommutative
  def ==(other)
    equal?(other) || self.class == other.class && args.first == other.args.first && contents == other.contents
  end
  alias :eql? :==
end


# Symbolic addition.
class Add < NaryFunction
  include Commutative
  def apply(obj) obj.add(self) end
  def self.make(*ops)
    if ops.empty?
      0
    elsif ops.size == 1
      ops.first
    else
      Add.new(*ops)
    end
  end
  def convert
    # flatten nested adds
    ops = args.collect do |op|
      op = op.convert
      op.is_a?(Add) ? op.args : op
    end
    ops.flatten!
    # fold nums
    value = 0
    ops.select! do |op|
      if op.is_a?(Numeric)
        value += op
        false
      else
        true
      end
    end
    # push back the resulting num
    value = value.convert
    ops << value unless value == 0 # a+0 --> a
    # recreate add
    Add.make(*ops)
  end
  def revert
    pos = []; neg = []
    args.each do |arg|
      arg = arg.revert
      begin
        rest = arg.extract_minus_one
        if rest.nil?
          pos << arg
        else
          neg << rest
        end
      rescue NoMethodError
        pos << arg
      end
    end
    if !pos.empty? && !neg.empty?
      Add.make(*pos) - Add.make(*neg) # (a+b)-(c+d)
    elsif !neg.empty?
      -Add.make(*neg) # -(a+b)
    else
      Add.make(*pos) # a+b
    end
  end
  def collect
    # attempt to collect common subexpressions: a*b+a*c-3*d --> a*(b+c)-3*d
    add_muls = args.collect do |arg|
      ops = arg.is_a?(Multiply) ? arg.args.dup : [arg]
      ops.collect! do |op|
        if op.is_a?(Numeric)
          # negative nums are converted to product of -1 and absolute value of the num, -3 --> -1*3
          # in order to perform collection of the nums like: 3*a-3*b --> 3*(a-b)
          !op.is_a?(Complex) && op < 0 && op != -1 ? [-1, op.abs] : op
        else
          op
        end
      end
      ops.flatten!
      ops
    end
    add_muls.flatten.each do |try|
      # it makes no sense factoring out the unit value
      unless try == 1
        # try is a term which can possibly be factored out
        found = []; not_found = []
        add_muls.each do |mul|
          # attempt to split the product into the try*rest
          rest = Symbolic.split_args(mul, try)
          if rest.nil?
            not_found << mul # try was not found in product at all
          elsif rest.empty?
            found << 1 # the product consists of the only term, try, hence: try --> try*1
          else
            found << rest # try was found and successfully eliminated
          end
        end
        if found.size > 1
          # it is only worth to move try out of the braces if it is found in more than two add operands
          # [found]*try + [not_found]
          obj = try*Add.make(*found.collect{|mul| Multiply.make(*mul)}).collect
          return not_found.empty? ? obj : obj + Add.make(*not_found.collect{|mul| Multiply.make(*mul)}).collect
        end
      end
    end
    super # nothing could be done at this level; collect the arguments
  end
end


# Symbolic multiplication.
class Multiply < NaryFunction
  include Commutative
  def apply(obj) obj.multiply(self) end
  def self.make(*ops)
    if ops.empty?
      1
    elsif ops.size == 1
      ops.first
    else
      Multiply.new(*ops)
    end
  end
  def convert
    # flatten nested muls
    ops = args.collect do |op|
      op = op.convert
      op.is_a?(Multiply) ? op.args : op
    end
    ops.flatten!
    # fold nums
    value = 1
    ops.select! do |op|
      if op.is_a?(Numeric)
        return 0 if op == 0 # a*0 --> 0
        value *= op
        false
      else
        true
      end
    end
    # push back the resulting num
    value = value.convert
    ops << value unless value == 1 # a*1 --> a
    # recreate add
    Multiply.make(*ops)
  end
  def revert
    negate = false
    rest = []
    args.each do |arg|
      arg = arg.revert
      if arg.is_a?(Minus)
        negate = !negate
        rest << arg.arg
      else
        begin
          abs = arg.extract_minus_one
          if abs.nil?
            rest << arg
          else
            negate = !negate
            rest << abs unless abs == 1
          end
        rescue NoMethodError
          rest << arg
        end
      end
    end
    nums = []; dens = [] # divd/divs
    rest.each do |arg|
      if arg.is_a?(Divide) && arg.args.size == 2
        nums << arg.args.first unless arg.args.first == 1
        dens << arg.args.last
      elsif arg.is_a?(Rational)
        nums << arg.numerator unless arg.numerator == 1
        dens << arg.denominator
      else
        nums << arg
      end
    end
    if !nums.empty? && !dens.empty?
      obj = Multiply.make(*nums)/Multiply.make(*dens)
    elsif !nums.empty?
      obj = Multiply.make(*nums)
    elsif !dens.empty?
      obj = 1/Multiply.make(*dens)
    end
    negate ? -obj : obj
  end
  def expand
    args.each_index do |i|
      if args[i].is_a?(Add)
        # a*(b+c)*d --> a*b*d + a*c*d
        ops = args.dup; ops.delete_at(i)
        rest = Multiply.make(*ops)
        return Add.make(*args[i].args.collect{|arg| arg*rest}).expand
      end
    end
    super # expand the args as the last resort
  end
  def collect
    bases = {}; bases.default = []
    args.each do |arg|
      if arg.is_a?(Power) && arg.args.size == 2 # only a**b is caught for now
        # have to use += operation due to aliased Hash#default value
        bases[arg.args.first] += [arg.args.last]
      else
        bases[arg] += [1] # a --> a**1
      end
    end
    Multiply.make(*bases.keys.collect{|base| base**Add.make(*bases[base])})
  end
  def extract_minus_one
    found = false
    rest = []
    args.each do |arg|
      if !found && !arg.is_a?(Complex) && arg.is_a?(Numeric) && arg < 0 # TODO reimplement with Numeric#extract_minus_one
        found = true
        rest << arg.abs unless arg == -1
      else
        rest << arg
      end
    end
    found ? Multiply.make(*rest) : nil
  end
end


# Symbolic subtraction.
class Subtract < NaryFunction
  include Noncommutative
  def apply(obj) obj.subtract(self) end
  def convert
    # a-b --> a+(-1)*b
    Add.new(*args[1..-1].collect{|op| (-1)*op}.unshift(args.first)).convert
  end
end


# Symbolic division.
class Divide < NaryFunction
  include Noncommutative
  def apply(obj) obj.divide(self) end
  def convert
    # a/b --> a*b**(-1)
    Multiply.new(*args[1..-1].collect{|op| op**(-1)}.unshift(args.first)).convert
  end
end


# Symbolic raise-to-power.
class Power < NaryFunction
  include Noncommutative
  def apply(obj) obj.power(self) end
  def convert
    base = args.first.convert
    power = Multiply.make(*args[1..-1]).convert
    if base == 0 && power == 0
      1 # 0**0 --> 1
    elsif power == 0
      1 # a**0 --> 1
    elsif base == 0
      0 # 0**a --> 0
    elsif power == 1
      base # a**1 --> a
    else
      Power.new(base, power)
    end
  end
  def revert
    rest = args.collect{|arg| arg.revert}
    if rest.size == 2
      if rest.last == -1
        return 1/rest.first # a**(-1) -- > 1/a
      elsif rest.last.is_a?(Minus)
        return 1/(rest.first**rest.last.arg) # a**(-b) --> 1/(a**b)
      end
    end
    Power.new(*rest)
  end
  def expand
    base = args.first.expand
    if base.is_a?(Multiply) && args.size == 2 # do not expand in case of non-trivial power
      # (a*b)**3 --> a**3 * b**3
      power = args.last.expand
      return Multiply.make(*base.args.collect {|arg| arg**power}).expand
    end
    powers = args[1..-1].collect {|arg| arg.expand}
    if powers.size == 1 && powers.first.is_a?(Add)
      # a**(b+c) --> a**b * a**c
      return Multiply.make(*powers.first.args.collect {|arg| base**arg}).expand
    end
    super # expand the args as the last resort
  end
  # TODO where is #collect ???
end


# Symbolic exponential function.
class Exp < UnaryFunction
  def apply(obj) obj.exp(self) end
  def convert
    op = arg.convert
    op.is_a?(Numeric) ? ::Math.exp(op) : Exp.new(op)
  end
end


# Symbolic natural logarithm function.
class Log < UnaryFunction
  def apply(obj) obj.log(self) end
  def convert
    op = arg.convert
    op.is_a?(Numeric) ? ::Math.log(op) : Log.new(op)
  end
end


# Visitor class which performs full symbolic differentiation of expression.
class Differ
  attr_reader :diffs, :result
  def initialize(diffs = {})
    @diffs = Differ.coerce(diffs)
    ary = @diffs.flatten
    @zero = @diffs.empty?
    @unit = ary.size == 2 && ary.last == 1 # true in case of {???=>1} and false otherwise
  end
  def apply!(obj)
    obj.convert.apply(self)
    result
  end
  def symbol(obj)
    if zero?
      @result = obj
    elsif unit?
      @result = ({obj=>1} == diffs ? 1 : 0)
    else
      diffs_seq(obj)
    end
  end
  def numeric(obj)
    @result = zero? ? obj : 0
  end
  def add(obj)
    # (a+b)' --> a' + b'
    @result = Add.make(*obj.args.collect {|arg| apply!(arg)}).convert
    # no need process the arguments with self.class.run() explicitly
  end
  def multiply(obj)
    if zero?
      @result = Multiply.new(*obj.args.collect {|arg| apply!(arg)}).convert
    elsif unit?
      # (a*b)' --> a'*b + a*b'
      rest = obj.args.dup
      term = rest.shift
      rest_mul = Multiply.make(*rest)
      lt = apply!(term)*self.class.new.apply!(rest_mul)
      rt = self.class.new.apply!(term)*(rest.size > 1 ? apply!(rest_mul) : apply!(rest.first))
      @result = Add.new(lt, rt).convert
    else
      diffs_seq(obj)
    end
  end
  def power(obj)
    if zero?
      @result = Power.new(*obj.args.collect {|arg| apply!(arg)}).convert
    elsif unit?
      raise "expected Power instance in a canonicalized form" unless obj.args.size == 2
      base, power = obj.args
      # (a^b)' --> a^b*(ln(a)*b' + b/a*a')
      @result = (obj*(apply!(power)*Log.new(base) + apply!(base)*power/base)).convert
    else
      diffs_seq(obj)
    end
  end
  def exp(obj)
    if zero?
      @result = Exp.new(apply!(obj.arg)).convert
    elsif unit?
      # exp(a)' --> exp(a)*a'
      @result = (obj*apply!(obj.arg)).convert
    else
      diffs_seq(obj)
    end
  end
  def log(obj)
    if zero?
      @result = Log.new(apply!(obj.arg)).convert
    elsif unit?
      # ln(a)' --> a'/a
      @result = (apply!(obj.arg)/obj).convert
    else
      diffs_seq(obj)
    end
  end
  def self.coerce(diffs)
    diffs.is_a?(Hash) ? diffs : {diffs=>1} # TODO validity check
  end
  def self.diffs_each(diffs, &block)
    diffs.each do |k,v|
      (1..v).each do
        yield(k)
      end
    end
  end
  protected
  def zero?; @zero end
  def unit?; @unit end
  private
  def diffs_seq(obj)
    @result = obj
    Differ.diffs_each(diffs) do |diff|
      @result = self.class.new(diff).apply!(@result)
    end
  end
end # Differ


#
class Traverser
  def plus(obj) traverse_unary(obj) end
  def minus(obj) traverse_unary(obj) end
  def exp(obj) traverse_unary(obj) end
  def log(obj) traverse_unary(obj) end
  def add(obj) traverse_nary(obj) end
  def multiply(obj) traverse_nary(obj) end
  def subtract(obj) traverse_nary(obj) end
  def divide(obj) traverse_nary(obj) end
  def power(obj) traverse_nary(obj) end
  protected
  def traverse_unary(obj)
    obj.arg.apply(self)
  end
  def traverse_nary(obj)
    obj.args.each do |arg|
      arg.apply(self)
    end
  end
end # Traverser


# Default precedence computer.
#
# Employed by emitters to judge the placement of the braces around subexpressions.
# That is, the subexpressions with higher precedence which are a part of the expression with lower precedence
# must be enclosed into round braces to maintain the proper evaluation order.
class PrecedenceComputer
  def numeric(obj) obj.is_a?(Complex) || obj < 0 ? 0 : 100 end
  def symbol(obj) 100 end
  def plus(obj) 1 end
  def minus(obj) 1 end
  def add(obj) 10 end
  def subtract(obj) 10 end
  def multiply(obj) 20 end
  def divide(obj) 20 end
  def power(obj) 30 end
  def exp(obj) 100 end
  def log(obj) 100 end
end # PrecedenceComputer


# Default symbolic expression renderer.
#
# Used by Expression#to_s to convert symbolic expression to string.
#
# In order to render a symbolic expression, the Emitter instance should be passed to Expression#apply method of the expression.
# The rendered string is the obtained with #to_s method.
class Emitter
  def initialize(pc = PrecedenceComputer.new)
    @out = String.new
    @pc = pc
  end
  # Returns string representation of the expression to which self has been applied.
  def to_s() @out.to_s end
  def emit!(obj) obj.apply(self); to_s end
  def numeric(obj) @out << obj.to_s end
  def symbol(obj) @out << obj.to_s end
  def plus(obj) op("+", obj) end
  def minus(obj) op("-", obj) end
  def add(obj) comm_op("+", obj) end
  def subtract(obj) ncomm_op("-", obj) end
  def multiply(obj) comm_op("*", obj) end
  def divide(obj) ncomm_op("/", obj) end
  def power(obj) ncomm_op("**", obj) end
  def exp(obj) unary_func("exp", obj) end
  def log(obj) unary_func("log", obj) end
  private
  def prec(obj) obj.apply(@pc) end
  def unary_func(op, obj)
    @out << op << "("
    obj.arg.apply(self)
    @out << ")"
  end
  def op(op, obj)
    if prec(obj) >= prec(obj.arg)
      @out << op
      obj.arg.apply(self)
    else
      @out << op << "("
      obj.arg.apply(self)
      @out << ")"
    end
  end
  def comm_op(op, obj)
    op_prec = prec(obj)
    comm_arg(op_prec, obj.args.first)
    obj.args[1..-1].each do |arg|
      @out << op
      comm_arg(op_prec, arg)
    end
  end
  def ncomm_op(op, obj)
    op_prec = prec(obj)
    comm_arg(op_prec, obj.args.first)
    obj.args[1..-1].each do |arg|
      @out << op
      ncomm_arg(op_prec, arg)
    end
  end
  def comm_arg(op_prec, arg)
    if op_prec <= prec(arg)
      arg.apply(self)
    else
      @out << "("
      arg.apply(self)
      @out << ")"
    end
  end
  def ncomm_arg(op_prec, arg)
    if op_prec < prec(arg)
      arg.apply(self)
    else
      @out << "("
      arg.apply(self)
      @out << ")"
    end
  end
end # Emitter


#
class RubyEmitter < Emitter
  def symbol(obj) @out << ":" << obj.to_s end
  def numeric(obj)
    if obj.is_a?(Complex)
      @out << "Complex(" << obj.real.to_s << "," << obj.imag.to_s << ")"
    elsif obj.is_a?(Rational)
      @out << "Rational(" << obj.numerator.to_s << "," << obj.denominator.to_s << ")"
    else
      @out << obj.to_s
    end
  end
  def exp(obj) unary_func("Math.exp", obj) end
  def log(obj) unary_func("Math.log", obj) end
  def power(obj)
    power_op(obj, *obj.args)
  end
  private
  def power_op(obj, *ops)
    if ops.size > 1
      @out << "("
      power_op(obj, *ops[0..-2])
      @out << ")**"
    end
    braces = prec(obj) > prec(ops.last) && ops.size > 1
    @out << "(" if braces
    ops.last.apply(self)
    @out << ")" if braces
  end
end # RubyEmitter


#
class CEmitter < Emitter
  def numeric(obj)
    if obj.is_a?(Complex)
      @out << obj.real.to_s
      @out << "+" if obj.imag >= 0
      @out << obj.imag.to_s << "*_Complex_I"
    elsif obj.is_a?(Rational)
      f = obj.to_f
      i = obj.to_i
      @out << (i == f ? i : f).to_s
    else
      @out << obj.to_s
    end
  end
  def exp(obj) unary_func("exp", obj) end
  def log(obj) unary_func("log", obj) end
  def power(obj)
    power_op(obj, *obj.args)
  end
  private
  def power_op(obj, *ops)
    if ops.size > 1
      @out << "pow("
      power_op(obj, *ops[0..-2])
      @out << ","
      ops.last.apply(self)
      @out << ")"
    else
      ops.last.apply(self)
    end
  end
end # CEmitter


end # Symbolic
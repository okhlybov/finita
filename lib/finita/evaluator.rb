require "autoc"
require "finita/common"


module Finita


class Evaluator
  Symbolic.freezing_new(self)
  attr_reader :hash, :expression, :result
  def initialize(expression, result)
    # TODO merge attribute is not needed
    @expression = Symbolic.simplify(expression)
    @result = result
    @hash = expression.hash ^ result.hash # TODO
  end
  def integer?
    result == Integer
  end
  def float?
    result == Float
  end
  def complex?
    result == Complex
  end
  def ==(other)
    equal?(other) || self.class == other.class && expression == other.expression && result == other.result
  end
  alias :eql? :==
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < AutoC::Type
    class << self
      alias :__new__ :new
      def new(owner, problem_code)
        problem_code.bound!(owner) {__new__(owner, problem_code)}
      end
    end
    @@count = 0
    attr_reader :hash, :instance
    def entities
      @entities.nil? ? @entities = Collector.new.apply!(@evaluator.expression).instances.collect {|o| o.code(@problem_code)} : @entities
    end
    def priority
      AutoC::Priority::DEFAULT + 1
    end
    def initialize(evaluator, problem_code)
      @evaluator = evaluator
      @problem_code = problem_code
      @instance = "#{@problem_code.type}#{@@count += 1}"
      @cresult = CType[evaluator.result]
      @problem_code.defines << :FINITA_COMPLEX if evaluator.complex?
      @hash = @evaluator.hash
      super("FinitaEvaluator")
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @evaluator == other.instance_variable_get(:@evaluator)
    end
    def expression
      @evaluator.expression
    end
    def write_intf(stream)
      stream << %$#{extern} #{@cresult} #{instance}(int, int, int);$
    end
    def write_defs(stream)
      stream << %$
        FINITA_ARGSUSED
        #{@cresult} #{instance}(int x, int y, int z) {
          #{@cresult} value;
          FINITA_ENTER;
          value = #{CEmitter.new.emit!(@evaluator.expression)};
          FINITA_RETURN(value);
        }
      $
    end
  end # Code
end # Evaluator


def self.numeric_instances_hash(&block)
  Hash[[Integer, Float, Complex].collect {|type| [type, yield(type)]}]
end


NumericArrayCode = numeric_instances_hash do |type|
  Class.new(AutoC::Vector) do
    @@fprintf_stmt = {
      Integer => %$fprintf(file, "%d\\t%d\\n", index, value)$,
      Float => %$fprintf(file, "%d\\t%e\\n", index, value)$,
      Complex => %$fprintf(file, "%d\\t%e+i(%e)\\n", index, creal(value), cimag(value))$
    }
    def initialize(type)
      super("Finita#{type}Array", {:type=>CType[type], :forward =>%$#include <stdio.h>$})
      @result = type
    end
    def write_intf(stream)
      super
      stream << %$#{extern} void #{dump}(#{type}*, FILE*);$
    end
    def write_defs(stream)
      super
      stream << %$
        void #{dump}(#{type}* self, FILE* file) {
          size_t index;
          #{assert}(self);
          #{assert}(file);
          for(index = 0; index < #{size}(self); ++index) {
            #{CType[@result]} value = #{get}(self, index);
            #{@@fprintf_stmt[@result]};
          }
        }
      $
    end
  end.new(type)
end


NodeCode = Class.new(Type) do
  def initialize; super("FinitaNode") end
  def write_intf(stream)
    stream << %$
      typedef struct {
        int field, x, y, z;
        size_t hash;
      } #{type};
      #{extern} #{type} #{new}(int, int, int, int);
      #{extern} int #{equal}(#{type}, #{type});
      #{extern} int #{less}(#{type}, #{type});
    $
  end
  def write_defs(stream)
    stream << %$
      #define SIGN2LSB(x) ((abs(x) << 1) | (x < 0))
      #{type} #{new}(int field, int x, int y, int z) {
        #{type} result;
        FINITA_ENTER;
        #{assert}(field >= 0);
        result.field = field;
        result.x = x;
        result.y = y;
        result.z = z;
        /* abs(x|y|z) < 2^9 is implied; extra bit is reserved for the sign */
        result.hash = FinitaHashMix(((SIGN2LSB(x) & 0x3FF) | ((SIGN2LSB(y) & 0x3FF) << 10) | ((SIGN2LSB(z) & 0x3FF) << 20)) ^ (field << 30));
        FINITA_RETURN(result);
      }
      #undef SIGN2LSB
      int #{equal}(#{type} lt, #{type} rt) {
        FINITA_ENTER;
        FINITA_RETURN(lt.field == rt.field && lt.x == rt.x && lt.y == rt.y && lt.z == rt.z);
      }
      int #{less}(#{type} lt, #{type} rt) {
        #{abort}(); /* TODO */
      }
    $
  end
  def ctor(obj) "#{obj} = #{new}(0, 0, 0, 0)" end
  def dtor(obj) end
  def copy(dst, src) "(#{dst}) = (#{src})" end
  def identify(obj) "(#{obj}).hash" end
end.new # NodeCode


NodeArrayCode = Class.new(AutoC::Vector) do
  def entities; super << NodeCode end
end.new("FinitaNodeArray", NodeCode) # NodeArrayCode


NodeSetCode = Class.new(AutoC::HashSet) do
  def entities; super << NodeCode end
end.new("FinitaNodeSet", NodeCode) # NodeSetCode


NodeIndexMapCode = Class.new(AutoC::HashMap) do
  def entities; super << NodeCode end
end.new("FinitaNodeIndexMap", NodeCode, {:type=>"size_t"}) # NodeIndexMapCode


NodeCoordCode = Class.new(Type) do
  def entities; super << NodeCode end
  def initialize; super("FinitaNodeCoord") end
  def write_intf(stream)
    stream << %$
      typedef struct {
        #{NodeCode.type} row, column;
        size_t hash;
      } #{type};
      #{extern} #{type} #{new}(#{NodeCode.type}, #{NodeCode.type});
      #{extern} int #{equal}(#{type}, #{type});
    $
  end
  def write_defs(stream)
    stream << %$
      #{type} #{new}(#{NodeCode.type} row, #{NodeCode.type} column) {
        #{type} result;
        FINITA_ENTER;
        result.row = row;
        result.column = column;
        result.hash = #{NodeCode.identify("row")} ^ (#{NodeCode.identify("column")} << 1);
        FINITA_RETURN(result);
      }
      int #{equal}(#{type} lt, #{type} rt) {
        FINITA_ENTER;
        FINITA_RETURN(#{NodeCode.equal("lt.row", "rt.row")} && #{NodeCode.equal("lt.column", "rt.column")});
      }
    $
  end
  def ctor(obj) end
  def dtor(obj) end
  def copy(dst, src) "(#{dst}) = (#{src})" end
  def identify(obj) "(#{obj}).hash" end
end.new # NodeCoordCode


SparsityPatternCode = Class.new(AutoC::HashSet) do |type|
  def entities
    super << NodeCoordCode
  end
  def initialize(type)
    super(type, NodeCoordCode)
  end
end.new("FinitaSparsityPattern")


FunctionCode = numeric_instances_hash do |type|
  Class.new(Type) do
    attr_reader :type
    def initialize(type)
      super("Finita#{type}Function")
      @ctype = CType[type]
    end
    def write_intf(stream)
      stream << %$typedef #{@ctype} (*#{@type})(int,int,int);$
    end
    def ctor(obj) end
    def dtor(obj) end
    def identify(obj) "((size_t)#{obj})" end
    def equal(lt, rt) "(#{lt}) == (#{rt})" end
    def copy(dst, src) "(#{dst}) = (#{src})" end
  end.new(type)
end # FunctionCode


FunctionListCode = numeric_instances_hash do |type|
  Class.new(AutoC::List) do
    def entities; super << @function_code end
    def initialize(type)
      @ctype = CType[type]
      @function_code = FunctionCode[type]
      super("Finita#{type}FunctionList", @function_code)
    end
    def write_intf(stream)
      super
      stream << %$#{extern} #{@ctype} #{summate}(#{type}*, int, int, int);$
    end
    def write_defs(stream)
      super
      stream << %$
        #{@ctype} #{summate}(#{type}* self, int x, int y, int z) {
          #{@ctype} result = 0;
          #{it} it;
          FINITA_ENTER;
          #{assert}(self);
          #{itCtor}(&it, self);
          while(#{itMove}(&it)) {
            result += #{itGet}(&it)(x, y, z);
          }
          FINITA_RETURN(result);
        }
      $
    end
  end.new(type)
end # FunctionListCode


FunctionArrayCode = numeric_instances_hash do |type|
  Class.new(AutoC::Vector) do
    def entities; super + [NodeCode, @function_code, @function_list_code] end
    def initialize(type)
      @ctype = CType[type]
      @function_code = FunctionCode[type]
      @function_list_code = FunctionListCode[type]
      super("Finita#{type}FunctionArray", @function_list_code)
    end
    def write_intf(stream)
      super
      stream << %$#{extern} void #{merge}(#{type}*, size_t, #{@function_code.type});$
    end
    def write_defs(stream)
      super
      stream << %$
        void #{merge}(#{type}* self, size_t index, #{@function_code.type} fp) {
          FINITA_ENTER;
          #{assert}(self);
          #{assert}(fp);
          #{@function_list_code.push}(#{get}(self, index), fp);
          FINITA_LEAVE;
        }
      $
    end
  end.new(type)
end # FunctionArrayCode


SparseMatrixCode = numeric_instances_hash do |type|
  Class.new(AutoC::HashMap) do
    def entities; super + [NodeCoordCode, @function_code, @function_list_code] end
    def initialize(type)
      @type = type
      @ctype = CType[type]
      @function_code = FunctionCode[type]
      @function_list_code = FunctionListCode[type]
      super("Finita#{type}SparseMatrix", NodeCoordCode, @function_list_code)
    end
    def write_intf(stream)
      super
      stream << %$#{extern} void #{merge}(#{type}*, #{NodeCode.type}, #{NodeCode.type}, #{@function_code.type});$
    end
    def write_defs(stream)
      super
      stream << %$
        void #{merge}(#{type}* self, #{NodeCode.type} row, #{NodeCode.type} column, #{@function_code.type} fp) {
          #{@function_list_code.type}* list;
          #{NodeCoordCode.type} node;
          FINITA_ENTER;
          node = #{NodeCoordCode.new}(row, column);
          #{assert}(self);
          #{assert}(fp);
          if(#{containsKey}(self, node)) {
            list = #{get}(self, node);
          } else {
            list = #{@function_list_code.new}();
            #{put}(self, node, list);
          }
          #{@function_list_code.add}(list, fp);
          FINITA_LEAVE;
        }
      $
    end
  end.new(type)
end # SparseMatrixCode


SparseVectorCode = numeric_instances_hash do |type|
  Class.new(AutoC::HashMap) do
    def entities; super + [NodeCode, @function_code, @function_list_code] end
    def initialize(type)
      @type = type
      @ctype = CType[type]
      @function_code = FunctionCode[type]
      @function_list_code = FunctionListCode[type]
      super("Finita#{type}SparseVector", NodeCode, @function_list_code)
    end
    def write_intf(stream)
      super
      stream << %$#{extern} void #{merge}(#{type}*, #{NodeCode.type}, #{@function_code.type});$
    end
    def write_defs(stream)
      super
      stream << %$
      void #{merge}(#{type}* self, #{NodeCode.type} node, #{@function_code.type} fp) {
        #{@function_list_code.type}* list;
        FINITA_ENTER;
        #{assert}(self);
        #{assert}(fp);
        if(#{containsKey}(self, node)) {
          list = #{get}(self, node);
        } else {
          list = #{@function_list_code.new}();
          #{put}(self, node, list);
        }
        #{@function_list_code.add}(list, fp);
        FINITA_LEAVE;
      }
    $
    end
  end.new(type)
end # SparseVectorCode


CallStackCode = Class.new(AutoC::List) do
  def initialize
    # FIXME : custom hash code
    super("FinitaCallStack", {:type=>"FinitaCallStackEntry", :equal=>"FinitaCallStackEntryEqual", :forward=>"
      #ifndef NDEBUG
        typedef struct {const char* func; const char* file; int line;} FinitaCallStackEntry;
      #endif
    "})
  end
  def write_intf(stream)
    stream << %$
      #ifndef NDEBUG
    $
    super
    stream << %$
      #endif
    $
  end
  def write_defs(stream)
    stream << %$
      #ifndef NDEBUG
    $
    stream << %$
      int FinitaCallStackEntryEqual(FinitaCallStackEntry lt, FinitaCallStackEntry rt) {
        return 0;
      }
    $
    super
    stream << %$
      #endif
    $
  end
end.new


end # Finita
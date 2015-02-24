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
  class Code < Finita::Type
    class << self
      alias :__new__ :new
      def new(owner, problem_code)
        problem_code.bound!(owner) {__new__(owner, problem_code)}
      end
    end
    @@count = 0
    attr_reader :hash, :instance
    def entities
      @entities.nil? ? @entities = super.concat(Collector.new.apply!(@evaluator.expression).instances.collect {|o| o.code(@problem_code)}) : @entities
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
    def ==(other)
      equal?(other) || self.class == other.class && @evaluator == other.instance_variable_get(:@evaluator)
    end
    alias :eql? :==
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


NodeCode = Class.new(UserDefinedType) do
  def initialize; super(:type => :FinitaNode, :equal => :FinitaNodeEqual, :identify => :FinitaNodeIdentify, :ctor => :FinitaNodeDefault, :less => nil) end
  def write_intf(stream)
    stream << %$
      typedef struct {
        int field, x, y, z;
        size_t hash;
      } #{type};
      #{extern} #{type} #{new}(int, int, int, int);
      #define #{equal}(lt,rt) ((lt).field == (rt).field && (lt).x == (rt).x && (lt).y == (rt).y && (lt).z == (rt).z)
      #define #{identify}(obj) ((obj).hash)
      #define #{ctor}(obj) ((obj) = #{new}(0,0,0,0))
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
    $
  end
end.new # NodeCode


NodeArrayCode = Class.new(AutoC::Vector) do
  def entities; super << NodeCode end
end.new(:FinitaNodeArray, NodeCode) # NodeArrayCode


NodeSetCode = Class.new(AutoC::HashSet) do
  def entities; super << NodeCode end
end.new(:FinitaNodeSet, NodeCode) # NodeSetCode


NodeIndexMapCode = Class.new(AutoC::HashMap) do
  def entities; super << NodeCode end
end.new(:FinitaNodeIndexMap, NodeCode, {:type => :size_t}) # NodeIndexMapCode


NodeCoordCode = Class.new(UserDefinedType) do
  def entities; super << NodeCode end
  def initialize; super(:type => :FinitaNodeCoord, :equal => :FinitaNodeCoordEqual, :identify => :FinitaNodeCoordIdentify) end
  def write_intf(stream)
    stream << %$
      typedef struct {
        #{NodeCode.type} row, column;
        size_t hash;
      } #{type};
      #{extern} #{type} #{new}(#{NodeCode.type}, #{NodeCode.type});
      #{extern} int #{equal}(#{type}, #{type});
      #define #{identify}(obj) ((obj).hash)
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
end.new # NodeCoordCode


SparsityPatternCode = Class.new(AutoC::HashSet) do |type|
  def entities; super << NodeCoordCode end
  def initialize(type) super(type, NodeCoordCode) end
end.new(:FinitaSparsityPattern)


FunctionCode = numeric_instances_hash do |type|
  Class.new(UserDefinedType) do
    attr_reader :type
    def initialize(type)
      super(:type => "Finita#{type}Function", :identify => "Finita#{type}Identify")
      @ctype = CType[type]
    end
    def write_intf(stream)
      stream << %$
        typedef #{@ctype} (*#{@type})(int,int,int);
        #define #{identify}(obj) ((size_t)obj)
      $
    end
  end.new(type)
end # FunctionCode


FunctionListCode = numeric_instances_hash do |type|
  Class.new(AutoC::List) do
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
        #{@ctype} #{summate}(#{type_ref} self, int x, int y, int z) {
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
    def initialize(type)
      @ctype = CType[type]
      @function_code = FunctionCode[type]
      super("Finita#{type}FunctionArray", AutoC::Reference.new(FunctionListCode[type]))
    end
    def write_intf(stream)
      super
      stream << %$#{extern} void #{merge}(#{type}*, size_t, #{@function_code.type});$
    end
    def write_defs(stream)
      super
      stream << %$
        void #{merge}(#{type}* self, size_t index, #{@function_code.type} fp) {
          #{element.type} obj;
          FINITA_ENTER;
          #{assert}(self);
          #{assert}(fp);
          #{element.push}(obj = #{get}(self, index), fp);
          #{element.dtor(:obj)};
          FINITA_LEAVE;
        }
      $
    end
  end.new(type)
end # FunctionArrayCode


SparseMatrixCode = numeric_instances_hash do |type|
  Class.new(AutoC::HashMap) do
    def initialize(type)
      @type = type
      @function_code = FunctionCode[type]
      super("Finita#{type}SparseMatrix", NodeCoordCode, AutoC::Reference.new(FunctionListCode[type]))
    end
    def write_intf(stream)
      super
      stream << %$#{extern} void #{merge}(#{type}*, #{NodeCode.type}, #{NodeCode.type}, #{@function_code.type});$
    end
    def write_defs(stream)
      super
      stream << %$
        void #{merge}(#{type}* self, #{NodeCode.type} row, #{NodeCode.type} column, #{@function_code.type} fp) {
          #{element.type} list;
          #{NodeCoordCode.type} node;
          FINITA_ENTER;
          node = #{NodeCoordCode.new}(row, column);
          #{assert}(self);
          #{assert}(fp);
          if(#{containsKey}(self, node)) {
            list = #{get}(self, node);
          } else {
            #{element.ctor(:list)};
            #{put}(self, node, list);
          }
          #{element.push}(list, fp);
          #{element.dtor(:list)}
          FINITA_LEAVE;
        }
      $
    end
  end.new(type)
end # SparseMatrixCode


SparseVectorCode = numeric_instances_hash do |type|
  Class.new(AutoC::HashMap) do
    def initialize(type)
      @type = type
      @function_code = FunctionCode[type]
      super("Finita#{type}SparseVector", NodeCode, AutoC::Reference.new(FunctionListCode[type]))
    end
    def write_intf(stream)
      super
      stream << %$#{extern} void #{merge}(#{type}*, #{NodeCode.type}, #{@function_code.type});$
    end
    def write_defs(stream)
      super
      stream << %$
      void #{merge}(#{type}* self, #{NodeCode.type} node, #{@function_code.type} fp) {
        #{element.type} list;
        FINITA_ENTER;
        #{assert}(self);
        #{assert}(fp);
        if(#{containsKey}(self, node)) {
          list = #{get}(self, node);
        } else {
          #{element.ctor(:list)};
          #{put}(self, node, list);
        }
        #{element.push}(list, fp);
        #{element.dtor(:list)}
        FINITA_LEAVE;
      }
    $
    end
  end.new(type)
end # SparseVectorCode


CallStackCode = Class.new(AutoC::List) do
  def initialize
    # FIXME : custom hash code
    super(:FinitaCallStack, {:type => :FinitaCallStackEntry, :identify => :FinitaCallStackEntryIdentify, :equal => :FinitaCallStackEntryEqual, :forward => %$
      #ifndef NDEBUG
        typedef struct {const char* func; const char* file; size_t line;} FinitaCallStackEntry;
      #endif
    $})
  end
  def write_intf(stream)
    debug_code(stream) {
      super
    }
  end
  def write_defs(stream)
    debug_code(stream) {
      stream << %$
        int FinitaCallStackEntryEqual(#{element.type} lt, #{element.type} rt) {
          return 0;
        }
        size_t FinitaCallStackEntryIdentify(#{element.type} obj) {
          return 0;
        }
      $
      super
    }
  end
end.new


end # Finita
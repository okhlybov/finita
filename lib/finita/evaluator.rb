require "autoc"
require "finita/common"
require "finita/generator"


module Finita


class Evaluator
  Symbolic.freezing_new(self)
  attr_reader :hash, :expression, :result
  def initialize(expression, result)
    @expression = Finita.simplify(expression)
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
  class Code < Finita::Code
    class << self
      alias :default_new :new
      def new(owner, problem_code)
        problem_code.bind!(owner) {default_new(owner, problem_code)}
      end
    end
    @@count = 0
    attr_reader :hash, :instance
    def entities
      super.concat(Collector.new.apply!(@evaluator.expression).instances.collect {|o| o.code(@problem_code)}).concat(@evaluator.complex? ? [Finita::ComplexCode] : [])
    end
    def initialize(evaluator, problem_code)
      @evaluator = evaluator
      @problem_code = problem_code
      @instance = "#{@problem_code.type}#{@@count += 1}"
      @cresult = CType[evaluator.result]
      @hash = @evaluator.hash
      super(:FinitaEvaluator)
    end
    def ==(other)
      equal?(other) || self.class == other.class && @evaluator == other.instance_variable_get(:@evaluator)
    end
    alias :eql? :==
    def expression
      @evaluator.expression
    end
    def write_decls(stream)
      stream << %$#{extern} #{@cresult} #{instance}(int, int, int);$
    end
    def write_defs(stream)
      stream << %$
        FINITA_ARGSUSED
        #{@cresult} #{instance}(int x, int y, int z) {
          #{@cresult} value;
          FINITA_ENTER;
          value = #{CEmitter.new.emit!(expression)};
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
      debug_code(stream) do
        stream << %$#{extern} void #{dump}(#{type}*, FILE*);$
      end
    end
    def write_defs(stream)
      super
      debug_code(stream) do
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
    end
  end.new(type)
end


NodeCode = Class.new(AutoC::UserDefinedType) do
  def initialize; super(:type => :FinitaNode, :equal => :FinitaNodeEqual, :identify => :FinitaNodeIdentify, :ctor => :FinitaNodeDefault, :less => nil) end
  def write_intf(stream)
    stream << %$
      #define XXH_INLINE_ALL
      #include "xxhash.h"
      typedef struct {
        union {
          uint64_t state;
          struct {
            unsigned short field;
            short x, y, z;
          };
        };
      } #{type};
      #{extern} #{type} #{new}(int, int, int, int);
      #define #{equal}(lt,rt) ((lt).state == (rt).state)
      #define #{identify}(obj) (XXH3_64bits(&obj, sizeof(obj)))
      #define #{ctor}(obj) ((obj) = #{new}(0,0,0,0))
    $
    debug_code(stream) do
      stream << %$#{extern} void #{dump}(#{type}, FILE*);$
    end
  end
  def write_defs(stream)
    stream << %$
      #{type} #{new}(int field, int x, int y, int z) {
        #{type} result;
        FINITA_ENTER;
        #{assert}(field >= 0);
        result.field = field;
        result.x = x;
        result.y = y;
        result.z = z;
        FINITA_RETURN(result);
      }
    $
    debug_code(stream) do
      stream << %$
        void #{dump}(#{type} self, FILE* file) {
          fprintf(file, "[%d](%d,%d,%d)", self.field, self.x, self.y, self.z);
        }
      $
    end
  end
end.new # NodeCode


NodeArrayCode = Class.new(AutoC::Vector) do
  def entities; super << NodeCode end
end.new(:FinitaNodeArray, NodeCode) # NodeArrayCode


NodeSetCode = Class.new(AutoC::HashSet) do
  def entities; super << NodeCode end
end.new(:FinitaNodeSet, NodeCode) # NodeSetCode


NodeQueueCode = Class.new(AutoC::Queue) do
  def entities; super << NodeCode end
end.new(:FinitaNodeQueue, NodeCode) # NodeQueueCode


NodeIndexMapCode = Class.new(AutoC::HashMap) do
  def entities; super << NodeCode end
end.new(:FinitaNodeIndexMap, NodeCode, {:type => :size_t}) # NodeIndexMapCode


NodeCoordCode = Class.new(AutoC::UserDefinedType) do
  def entities; super << NodeCode end
  def initialize; super(:type => :FinitaNodeCoord, :equal => :FinitaNodeCoordEqual, :identify => :FinitaNodeCoordIdentify) end
  def write_intf(stream)
    stream << %$
      typedef struct {
        #{NodeCode.type} row, column;
      } #{type};
      #{extern} #{type} #{new}(#{NodeCode.type}, #{NodeCode.type});
      #{extern} int #{equal}(#{type}, #{type});
      #define #{identify}(obj) (XXH3_64bits(&obj, sizeof(obj)))
    $
  end
  def write_defs(stream)
    stream << %$
      #{type} #{new}(#{NodeCode.type} row, #{NodeCode.type} column) {
        #{type} result;
        FINITA_ENTER;
        result.row = row;
        result.column = column;
        FINITA_RETURN(result);
      }
      int #{equal}(#{type} lt, #{type} rt) {
        FINITA_ENTER;
        FINITA_RETURN(#{NodeCode.equal("lt.row", "rt.row")} && #{NodeCode.equal("lt.column", "rt.column")});
      }
    $
  end
end.new # NodeCoordCode


NodeCoordQueueCode = Class.new(AutoC::Queue) do
  def entities; super << NodeCoordCode end
end.new(:FinitaNodeCoordQueue, NodeCoordCode) # NodeCoordQueueCode



SparsityPatternCode = Class.new(AutoC::HashSet) do |type|
  def entities; super << NodeCoordCode end
  def initialize(type) super(type, NodeCoordCode) end
  def write_intf(stream)
    super
    debug_code(stream) do
      stream << %$
        #{extern} void #{dump}(#{type_ref}, FILE*);
      $
    end
  end
  def write_defs(stream)
    super
    debug_code(stream) do
      stream << %$
         void #{dump}(#{type_ref} self, FILE* file) {
          #{it} it;
          #{itCtor}(&it, self);
          while(#{itMove}(&it)) {
            #{element.type} c = #{itGet}(&it);
            #{NodeCode.dump}(c.row, file);
            fputs(" : ", file);
            #{NodeCode.dump}(c.column, file);
            fputs(", ", file);
          }
          fputs("\\n", file);
         }
      $
    end
  end
end.new(:FinitaSparsityPattern)


FunctionCode = numeric_instances_hash do |type|
  Class.new(AutoC::UserDefinedType) do
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
          #{element.dtor(:list)};
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
        #{element.dtor(:list)};
        FINITA_LEAVE;
      }
    $
    end
  end.new(type)
end # SparseVectorCode


end # Finita
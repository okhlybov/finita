require "autoc"
require "finita/common"


module Finita


class Evaluator
  attr_reader :expression, :result
  def initialize(expression, result)
    # TODO merge attribute is not needed
    @expression = expression
    @result = result
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
  def hash
    expression.hash ^ result.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && expression == other.expression && result == other.result
  end
  alias :eql? :==
  def code(problem_code)
    Code.new(self, problem_code)
  end
  class Code < DataStructBuilder::Code
    class << self
      alias :__new__ :new
      def new(owner, problem_code)
        obj = __new__(owner, problem_code)
        problem_code << obj
      end
    end
    @@count = 0
    attr_reader :instance
    def entities; super + Collector.new.apply!(@evaluator.expression).instances.collect {|o| o.code(@problem_code)} end
    def priority
      CodeBuilder::Priority::DEFAULT + 1
    end
    def initialize(evaluator, problem_code)
      @evaluator = evaluator
      @problem_code = problem_code
      @instance = "#{@problem_code.type}#{@@count += 1}"
      @cresult = CType[evaluator.result]
      @problem_code.defines << :FINITA_COMPLEX if evaluator.complex?
      super("FinitaEvaluator")
    end
    def hash
      @evaluator.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @evaluator == other.instance_variable_get(:@evaluator)
    end
    def expression
      @evaluator.expression
    end
    def write_intf(stream)
      stream << %$#{@cresult} #{instance}(int, int, int);$
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
  Hash[[Integer, Float, Complex].collect {|type| [type, block.call(type)]}]
end


NumericArrayCode = numeric_instances_hash do |type|
  Class.new(DataStructBuilder::Vector) do
    @@fprintf_stmt = {
      Integer => %$fprintf(file, "%d\\t%d\\n", index, value)$,
      Float => %$fprintf(file, "%d\\t%e\\n", index, value)$,
      Complex => %$fprintf(file, "%d\\t%e+i(%e)\\n", index, creal(value), cimag(value))$
    }
    def initialize(type)
      super("Finita#{type}Array", {:type=>CType[type]})
      @result = type
    end
    def write_intf(stream)
      super
      stream << %$void #{dump}(#{type}*, FILE*);$
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


NodeCode = Class.new(DataStructBuilder::Code) do
  def initialize(*args)
    super
    @self_hash = {:type=>type, :hash=>hasher, :equal=>comparator}
  end
  def [](symbol)
    @self_hash[symbol]
  end
  def include?(symbol)
    @self_hash.include?(symbol)
  end
  def write_intf(stream)
    stream << %$
      typedef struct {
        int field, x, y, z;
        size_t hash;
      } #{type};
      #define SIGN2LSB(x) ((abs(x) << 1) | (x < 0))
      #{inline} #{type} #{new}(int field, int x, int y, int z) {
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
      #{inline} size_t #{hasher}(#{type} node) {
        return node.hash;
      }
      #{inline} int #{comparator}(#{type} lt, #{type} rt) {
        return lt.field == rt.field && lt.x == rt.x && lt.y == rt.y && lt.z == rt.z;
      }
    $
  end
end.new("FinitaNode") # NodeCode


NodeArrayCode = Class.new(DataStructBuilder::Vector) do
  def entities; super << NodeCode end
end.new("FinitaNodeArray", NodeCode) # NodeArrayCode


NodeSetCode = Class.new(DataStructBuilder::HashSet) do
  def entities; super << NodeCode end
end.new("FinitaNodeSet", NodeCode) # NodeSetCode


NodeIndexMapCode = Class.new(DataStructBuilder::HashMap) do
  def entities; super << NodeCode end
end.new("FinitaNodeIndexMap", NodeCode, {:type=>'size_t'}) # NodeIndexMapCode


NodeCoordCode = Class.new(DataStructBuilder::Code) do
  def entities; super << NodeCode end
  def initialize(*args)
    super
    @self_hash = {:type=>type, :hash=>hasher, :equal=>comparator}
  end
  def [](symbol)
    @self_hash[symbol]
  end
  def include?(symbol)
    @self_hash.include?(symbol)
  end
  def write_intf(stream)
    stream << %$
      typedef struct {
        #{NodeCode.type} row, column;
        size_t hash;
      } #{type};
      #{inline} #{type} #{new}(#{NodeCode.type} row, #{NodeCode.type} column) {
        #{type} result;
        result.row = row;
        result.column = column;
        result.hash = #{NodeCode.hasher}(row) ^ (#{NodeCode.hasher}(column) << 1);
        return result;
      }
      #{inline} size_t #{hasher}(#{type} node) {
        return node.hash;
      }
      #{inline} int #{comparator}(#{type} lt, #{type} rt) {
        return #{NodeCode.comparator}(lt.row, rt.row) && #{NodeCode.comparator}(lt.column, rt.column);
      }
    $
  end
end.new("FinitaNodeCoord") # NodeCoordCode


SparsityPatternCode = Class.new(DataStructBuilder::HashSet) do |type|
  def entities
    super + [NodeCoordCode]
  end
  def initialize(type)
    super(type, NodeCoordCode)
  end
end.new("FinitaSparsityPattern")


FunctionCode = numeric_instances_hash do |type|
  Class.new(CodeBuilder::Code) do
    attr_reader :type
    def initialize(type)
      @type = "Finita#{type}Function"
      @ctype = CType[type]
      @self_hash = {:type=>self.type}
    end
    def [](symbol)
      @self_hash[symbol]
    end
    def include?(symbol)
      @self_hash.include?(symbol)
    end
    def write_intf(stream)
      stream << %$typedef #{@ctype} (*#{@type})(int,int,int);$
    end
  end.new(type)
end # FunctionCode


FunctionListCode = numeric_instances_hash do |type|
  Class.new(DataStructBuilder::List) do
    def entities; super + [@function_code] end
    def initialize(type)
      @ctype = CType[type]
      @function_code = FunctionCode[type]
      super("Finita#{type}FunctionList", @function_code)
    end
    def write_intf(stream)
      super
      stream << %$#{@ctype} #{summate}(#{type}*, int, int, int);$
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
          while(#{itHasNext}(&it)) {
            result += #{itNext}(&it)(x, y, z);
          }
          FINITA_RETURN(result);
        }
      $
    end
  end.new(type)
end # FunctionListCode


FunctionArrayCode = numeric_instances_hash do |type|
  Class.new(DataStructBuilder::Vector) do
    def entities; super + [NodeCode, @function_code, @function_list_code] end
    def initialize(type)
      @ctype = CType[type]
      @function_code = FunctionCode[type]
      @function_list_code = FunctionListCode[type]
      super("Finita#{type}FunctionArray", @function_list_code)
    end
    def write_intf(stream)
      super
      stream << %$void #{merge}(#{type}*, size_t, #{@function_code.type});$
    end
    def write_defs(stream)
      super
      stream << %$
        void #{merge}(#{type}* self, size_t index, #{@function_code.type} fp) {
          FINITA_ENTER;
          #{assert}(self);
          #{assert}(fp);
          #{@function_list_code.add}(#{get}(self, index), fp);
          FINITA_LEAVE;
        }
      $
    end
  end.new(type)
end # FunctionArrayCode


SparseMatrixCode = numeric_instances_hash do |type|
  Class.new(DataStructBuilder::HashMap) do
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
      stream << %$void #{merge}(#{type}*, #{NodeCode.type}, #{NodeCode.type}, #{@function_code.type});$
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
  Class.new(DataStructBuilder::HashMap) do
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
      stream << %$void #{merge}(#{type}*, #{NodeCode.type}, #{@function_code.type});$
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


CallStackCode = Class.new(DataStructBuilder::List) do
  def initialize
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
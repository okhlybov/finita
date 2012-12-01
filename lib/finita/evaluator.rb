require 'singleton'
require 'data_struct'
require 'finita/common'


module Finita


class Evaluator
  attr_reader :expression, :type
  def initialize(expression, type)
    @expression = expression
    @type = type
  end
  def hash
    expression.hash ^ type.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && expression == other.expression && type == other.type
  end
  alias :eql? :==
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
    @@count = 0
    attr_reader :evaluator, :instance
    def entities; super + Collector.collect(evaluator.expression).instances.collect {|o| o.code(@problem_code)} end
    def initialize(evaluator, problem_code)
      @evaluator = evaluator
      @problem_code = problem_code
      @instance = "#{@problem_code.type}#{@@count += 1}"
      @ctype = Finita::NumericType[evaluator.type]
      @problem_code.defines << :FINITA_COMPLEX if evaluator.type == Complex
      super('FinitaCode')
    end
    def hash
      evaluator.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && evaluator == other.evaluator
    end
    def write_intf(stream)
      stream << %$#{@ctype} #{instance}(int, int, int);$
    end
    def write_defs(stream)
      stream << %$
        FINITA_ARGSUSED
        #{@ctype} #{instance}(int x, int y, int z) {
          return #{CEmitter.emit(evaluator.expression)};
        }
      $
    end
  end # Code
end # Evaluator


class NodeCode < DataStruct::Code
  include Singleton
  def initialize
    super('FinitaNode')
  end
  def write_intf(stream)
    # Thomas Wang's mixing algorithm, 32-bit version
    # http://www.concentric.net/~ttwang/tech/inthash.htm
    stream << %$
      FINITA_INLINE size_t FinitaHashMix(size_t hash) {
        hash = (hash ^ 61) ^ (hash >> 16);
        hash = hash + (hash << 3);
        hash = hash ^ (hash >> 4);
        hash = hash * 0x27d4eb2d;
        hash = hash ^ (hash >> 15);
        return hash;
      }
      typedef struct {
        int field, x, y, z;
        size_t hash;
      } #{type};
      #define SIGN2LSB(x) ((abs(x) << 1) | (x < 0))
      FINITA_INLINE #{type} #{new}(int field, int x, int y, int z) {
        #{type} result;
        #{assert}(field >= 0);
        result.field = field;
        result.x = x;
        result.y = y;
        result.z = z;
        /* abs(x|y|z) < 2^9 is implied; extra bit is reserved for the sign */
        result.hash = FinitaHashMix(((SIGN2LSB(x) & 0x3FF) | ((SIGN2LSB(y) & 0x3FF) << 10) | ((SIGN2LSB(z) & 0x3FF) << 20)) ^ (field << 30));
        return result;
      }
      #undef SIGN2LSB
      FINITA_INLINE size_t #{hasher}(#{type} node) {
        return node.hash;
      }
      FINITA_INLINE int #{comparator}(#{type} lt, #{type} rt) {
        return lt.field == rt.field && lt.x == rt.x && lt.y == rt.y && lt.z == rt.z;
      }
    $
  end
end # NodeCode


class NodeArrayCode < DataStruct::Array
  include Singleton
  attr_reader :node
  def entities; super + [node] end
  def initialize
    @node = NodeCode.instance
    super('FinitaNodeArray', node.type)
  end
end # NodeArrayCode


class NodeSetCode < DataStruct::Set
  include Singleton
  attr_reader :node
  def entities; super + [node] end
  def initialize
    @node = NodeCode.instance
    super('FinitaNodeSet', node.type, node.hasher, node.comparator)
  end
end # NodeSetCode


class NodeIndexMapCode < DataStruct::Map
  include Singleton
  attr_reader :node
  def entities; super + [node] end
  def initialize
    @node = NodeCode.instance
    super('FinitaNodeIndexMap', node.type, 'size_t', node.hasher, node.comparator)
  end
end # NodeIndexMapCode


class NodeCoordCode < DataStruct::Code
  include Singleton
  attr_reader :node
  def entities; super + [node] end
  def initialize
    super('FinitaNodeCoord')
    @node = NodeCode.instance
  end
  def write_intf(stream)
    stream << %$
      typedef struct {
        #{node.type} row, column;
        size_t hash;
      } #{type};
      #{inline} #{type} #{new}(#{node.type} row, #{node.type} column) {
        #{type} result;
        result.row = row;
        result.column = column;
        result.hash = FinitaHashMix(#{node.hasher}(row) ^ #{node.hasher}(column));
        return result;
      }
      #{inline} size_t #{hasher}(#{type} node) {
        return node.hash;
      }
      #{inline} int #{comparator}(#{type} lt, #{type} rt) {
        return #{node.comparator}(lt.row, rt.row) && #{node.comparator}(lt.column, rt.column);
      }
    $
  end
end # NodeCoordCode


class FuncListCode < DataStruct::List
  include Singleton
  def initialize
    super('FinitaFuncList', 'FinitaFunc', 'FinitaFuncComparator')
  end
  def write_intf(stream)
    stream << %$
      typedef void (*#{elementType})(void);
      #{inline} int #{comparator}(#{elementType} lt, #{elementType} rt) {
        return lt == rt;
      }
    $
    super
  end
end # FuncListCode


class FuncListArrayCode < DataStruct::Array
  include Singleton
  attr_reader :list
  def entities; super + [list] end
  def initialize
    @list = FuncListCode.instance
    super('FinitaFuncListArray', "#{list.type}*")
  end
end # FuncListArrayCode


class FuncNodeMapCode < DataStruct::Map
  include Singleton
  attr_reader :key, :list
  def entities; super + [key, list] end
  def initialize
    @list = FuncListCode.instance
    @key = NodeCode.instance
    super('FinitaFuncNodeMap', key.type, "#{list.type}*", key.hasher, key.comparator)
  end
end # FuncNodeMapCode


class FuncNodeCoordMapCode < DataStruct::Map
  include Singleton
  attr_reader :key, :list
  def entities; super + [key, list] end
  def initialize
    @list = FuncListCode.instance
    @key = NodeCoordCode.instance
    super('FinitaFuncNodeCoordMap', key.type, "#{list.type}*", key.hasher, key.comparator)
  end
end # FuncNodeMapCode


class AbstractEvaluationArrayCode < DataStruct::Structure
  attr_reader :returnType, :array
  def entities; super + [array] end
  def initialize(type, element_type, return_type)
    super(type, element_type)
    @returnType = return_type
    @array = FuncListArrayCode.instance
  end
  def write_intf(stream)
    stream << %$
      typedef #{array.type} #{type};
      typedef #{returnType} (*#{elementType})(int, int, int);
      void #{ctor}(#{type}*, size_t);
      void #{merge}(#{type}*, size_t, #{elementType});
      #{returnType} #{evaluate}(#{type}*, size_t, int, int, int);
    $
    super
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(#{type}* self, size_t size) {
        #{assert}(self);
        #{array.ctor}(self, size);
      }
      void #{merge}(#{type}* self, size_t index, #{elementType} fp) {
        #{array.elementType} list;
        #{assert}(self);
        #{assert}(#{array.within}(self, index));
        list = #{array.get}(self, index);
        if(!list) {
          list = #{array.list.new}();
          #{array.set}(self, index, list);
        }
        #{array.list.append}(list, (#{array.list.elementType})fp);
      }
      #{returnType} #{evaluate}(#{type}* self, size_t index, int x, int y, int z) {
        #{array.list.it} it;
        #{returnType} result = 0;
        #{assert}(self);
        #{assert}(#{array.within}(self, index));
        #{array.list.itCtor}(&it, #{array.get}(self, index));
        while(#{array.list.itHasNext}(&it)) result += ((#{elementType})#{array.list.itNext}(&it))(x, y, z);
        return result;
      }
    $
    super
  end
end


class IntegerEvaluationArrayCode < AbstractEvaluationArrayCode
  include Singleton
  def initialize
    super('FinitaIntegerEvaluationArray', 'FinitaIntegerFuncPtr', NumericType[Integer])
  end
end # IntegerEvaluationArrayCode



class FloatEvaluationArrayCode < AbstractEvaluationArrayCode
  include Singleton
  def initialize
    super('FinitaFloatEvaluationArray', 'FinitaFloatFuncPtr', NumericType[Float])
  end
end # FloatEvaluationArrayCode


class ComplexEvaluationArrayCode < AbstractEvaluationArrayCode
  include Singleton
  def initialize
    super('FinitaComplexEvaluationArray', 'FinitaComplexFuncPtr', NumericType[Complex])
  end
end # ComplexEvaluationArrayCode


EvaluationArrayCode = {
    Integer => IntegerEvaluationArrayCode.instance,
    Float => FloatEvaluationArrayCode.instance,
    Complex => ComplexEvaluationArrayCode.instance
}


class AbstractEvaluationVectorCode < DataStruct::Structure
  attr_reader :returnType, :map
  def entities; super + [map] end
  def initialize(type, element_type, return_type)
    super(type, element_type)
    @returnType = return_type
    @map = FuncNodeMapCode.instance
  end
  def write_intf(stream)
    stream << %$
      typedef #{map.type} #{type};
      typedef #{returnType} (*#{elementType})(int, int, int);
      void #{ctor}(#{type}*, size_t);
      void #{merge}(#{type}*, #{map.key.type}, #{elementType});
      #{returnType} #{get}(#{type}*, #{map.key.type});
    $
    super
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(#{type}* self, size_t bucket_size) {
        #{assert}(self);
        #{map.ctor}(self, bucket_size);
      }
      void #{merge}(#{type}* self, #{map.key.type} node, #{elementType} fp) {
        #{map.elementType} list;
        #{assert}(self);
        if(#{map.containsKey}(self, node)) {
          list = #{map.get}(self, node);
        } else {
          list = #{map.list.new}();
          #{map.put}(self, node, list);
        }
        #{map.list.append}(list, (#{map.list.elementType})fp);
      }
      #{returnType} #{get}(#{type}* self, #{map.key.type} node) {
        #{map.list.it} it;
        #{returnType} result = 0;
        #{assert}(self);
        #{assert}(#{map.containsKey}(self, node));
        #{map.list.itCtor}(&it, #{map.get}(self, node));
        while(#{map.list.itHasNext}(&it)) result += ((#{elementType})#{map.list.itNext}(&it))(node.x, node.y, node.z);
        return result;
      }
    $
    super
  end
end # AbstractEvaluationVectorCode


class IntegerEvaluationVectorCode < AbstractEvaluationVectorCode
  include Singleton
  def initialize
    super('FinitaIntegerEvaluationVector', 'FinitaIntegerFuncPtr', NumericType[Integer])
  end
end # IntegerEvaluationVectorCode


class FloatEvaluationVectorCode < AbstractEvaluationVectorCode
  include Singleton
  def initialize
    super('FinitaFloatEvaluationVector', 'FinitaFloatFuncPtr', NumericType[Float])
  end
end # FloatEvaluationVectorCode


class ComplexEvaluationVectorCode < AbstractEvaluationVectorCode
  include Singleton
  def initialize
    super('FinitaComplexEvaluationVector', 'FinitaComplexFuncPtr', NumericType[Complex])
  end
end # ComplexEvaluationVectorCode


EvaluationVectorCode = {
    Integer => IntegerEvaluationVectorCode.instance,
    Float => FloatEvaluationVectorCode.instance,
    Complex => ComplexEvaluationVectorCode.instance
}


class AbstractEvaluationMatrixCode < DataStruct::Structure
  attr_reader :returnType, :map
  def entities; super + [map] end
  def initialize(type, element_type, return_type)
    super(type, element_type)
    @returnType = return_type
    @map = FuncNodeCoordMapCode.instance
    @node = NodeCode.instance
  end
  def write_intf(stream)
    stream << %$
      typedef #{map.type} #{type};
      typedef #{returnType} (*#{elementType})(int, int, int);
      void #{ctor}(#{type}*, size_t);
      void #{merge}(#{type}*, #{@node.type}, #{@node.type}, #{elementType});
      #{returnType} #{get}(#{type}*, #{@node.type}, #{@node.type});
    $
    super
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(#{type}* self, size_t bucket_size) {
        #{assert}(self);
        #{map.ctor}(self, bucket_size);
      }
      void #{merge}(#{type}* self, #{@node.type} row, #{@node.type} column, #{elementType} fp) {
        #{map.key.type} node;
        #{map.elementType} list;
        #{assert}(self);
        node = #{map.key.new}(row, column);
        if(#{map.containsKey}(self, node)) {
          list = #{map.get}(self, node);
        } else {
          list = #{map.list.new}();
          #{map.put}(self, node, list);
        }
        #{map.list.append}(list, (#{map.list.elementType})fp);
      }
      #{returnType} #{get}(#{type}* self, #{@node.type} row, #{@node.type} column) {
        #{map.key.type} node;
        #{map.list.it} it;
        #{returnType} result = 0;
        #{assert}(self);
        node = #{map.key.new}(row, column);
        #{assert}(#{map.containsKey}(self, node));
        #{map.list.itCtor}(&it, #{map.get}(self, node));
        while(#{map.list.itHasNext}(&it)) result += ((#{elementType})#{map.list.itNext}(&it))(row.x, row.y, row.z);
        return result;
      }
    $
    super
  end
end # AbstractEvaluationMatrixCode


class IntegerEvaluationMatrixCode < AbstractEvaluationMatrixCode
  include Singleton
  def initialize
    super('FinitaIntegerEvaluationMatrix', 'FinitaIntegerFuncPtr', NumericType[Integer])
  end
end # IntegerEvaluationMatrixCode


class FloatEvaluationMatrixCode < AbstractEvaluationMatrixCode
  include Singleton
  def initialize
    super('FinitaFloatEvaluationMatrix', 'FinitaFloatFuncPtr', NumericType[Float])
  end
end # FloatEvaluationMatrixCode


class ComplexEvaluationMatrixCode < AbstractEvaluationMatrixCode
  include Singleton
  def initialize
    super('FinitaComplexEvaluationMatrix', 'FinitaComplexFuncPtr', NumericType[Complex])
  end
end # ComplexEvaluationMatrixCode


EvaluationMatrixCode = {
    Integer => IntegerEvaluationMatrixCode.instance,
    Float => FloatEvaluationMatrixCode.instance,
    Complex => ComplexEvaluationMatrixCode.instance
}


end # Finita
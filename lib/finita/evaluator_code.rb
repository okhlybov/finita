require 'singleton'
require 'data_struct'
require 'code_builder'


module Finita


NumericType = {
  ::Integer => 'int',
  ::Float => 'double',
  ::Complex => '_Complex double'
}


class Node < DataStruct::Struct
  include Singleton
  def initialize
    super('FinitaNode', nil)
  end
  def write_intf(stream)
    stream << %$
      static size_t FinitaHashMix(size_t hash) {
        /* Thomas Wang's mixing algorithm */
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
      static #{type} #{new}(int field, int x, int y, int z) {
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
      static size_t #{hasher}(#{type} node) {
        return node.hash;
      }
      static int #{comparator}(#{type} lt, #{type} rt) {
        return lt.field == rt.field && lt.x == rt.x && lt.y == rt.y && lt.z == rt.z;
      }
    $
  end
end # Node


class NodeCoord < DataStruct::Struct
  include Singleton
  attr_reader :node
  def entities; super + [node] end
  def initialize
    super('FinitaNodeCoord', nil)
    @node = Node.instance
  end
  def write_intf(stream)
    stream << %$
      typedef struct {
        #{node.type} row, column;
        size_t hash;
      } #{type};
      static #{type} #{new}(#{node.type} row, #{node.type} column) {
        #{type} result;
        result.row = row;
        result.column = column;
        result.hash = FinitaHashMix(#{node.hasher}(row) ^ #{node.hasher}(column));
        return result;
      }
      static size_t #{hasher}(#{type} node) {
        return node.hash;
      }
      static int #{comparator}(#{type} lt, #{type} rt) {
        return #{node.comparator}(lt.row, rt.row) && #{node.comparator}(lt.column, rt.column);
      }
    $
  end
end # NodeCoord


class FuncList < DataStruct::List
  include Singleton
  def initialize
    super('FinitaFuncList', 'FinitaFunc', 'FinitaFuncComparator')
  end
  def write_intf(stream)
    stream << %$
      typedef void (*#{elementType})(void);
      static int #{comparator}(#{elementType} lt, #{elementType} rt) {
        return lt == rt;
      }
    $
    super
  end
end # FuncList


class FuncNodeMap < DataStruct::Map
  include Singleton
  attr_reader :key, :list
  def entities; super + [key, list] end
  def initialize
    @list = FuncList.instance
    @key = Node.instance
    super('FinitaFuncNodeMap', key.type, "#{list.type}*", key.hasher, key.comparator)
  end
end # FuncNodeMap


class FuncNodeCoordMap < DataStruct::Map
  include Singleton
  attr_reader :key, :list
  def entities; super + [key, list] end
  def initialize
    @list = FuncList.instance
    @key = NodeCoord.instance
    super('FinitaFuncNodeCoordMap', key.type, "#{list.type}*", key.hasher, key.comparator)
  end
end # FuncNodeMap


class EvaluationVector < DataStruct::Struct
  attr_reader :returnType, :map
  def entities; super + [map] end
  def initialize(type, element_type, return_type)
    super(type, element_type)
    @returnType = return_type
    @map = FuncNodeMap.instance
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
        #{assert}(self);
        #{map.list.append}(#{map.containsKey}(self, node) ? #{map.get}(self, node) : #{map.list.new}(), (#{map.list.elementType})fp);
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
end # EvaluationVector


class IntegerEvaluationVector < EvaluationVector
  include Singleton
  def initialize
    super('FinitaIntegerEvaluationVector', 'FinitaIntegerFuncPtr', NumericType[::Integer])
  end
end # FloatEvaluationVector


class FloatEvaluationVector < EvaluationVector
  include Singleton
  def initialize
    super('FinitaFloatEvaluationVector', 'FinitaFloatFuncPtr', NumericType[::Float])
  end
end # FloatEvaluationVector


class ComplexEvaluationVector < EvaluationVector
  include Singleton
  def initialize
    super('FinitaComplexEvaluationVector', 'FinitaComplexFuncPtr', NumericType[::Complex])
  end
end # ComplexEvaluationVector


EvaluationVectorCode = {
    ::Integer => IntegerEvaluationVector.instance,
    ::Float => FloatEvaluationVector.instance,
    ::Complex => ComplexEvaluationVector.instance
}


class EvaluationMatrix < DataStruct::Struct
  attr_reader :returnType, :map
  def entities; super + [map] end
  def initialize(type, element_type, return_type)
    super(type, element_type)
    @returnType = return_type
    @map = FuncNodeCoordMap.instance
    @node = Node.instance
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
        #{assert}(self);
        node = #{map.key.new}(row, column);
        #{map.list.append}(#{map.containsKey}(self, node) ? #{map.get}(self, node) : #{map.list.new}(), (#{map.list.elementType})fp);
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
end # EvaluationMatrix


class IntegerEvaluationMatrix < EvaluationMatrix
  include Singleton
  def initialize
    super('FinitaIntegerEvaluationMatrix', 'FinitaIntegerFuncPtr', NumericType[::Integer])
  end
end # FloatEvaluationMatrix


class FloatEvaluationMatrix < EvaluationMatrix
  include Singleton
  def initialize
    super('FinitaFloatEvaluationMatrix', 'FinitaFloatFuncPtr', NumericType[::Float])
  end
end # FloatEvaluationMatrix


class ComplexEvaluationMatrix < EvaluationMatrix
  include Singleton
  def initialize
    super('FinitaComplexEvaluationMatrix', 'FinitaComplexFuncPtr', NumericType[::Complex])
  end
end # ComplexEvaluationMatrix


EvaluationMatrixCode = {
    ::Integer => IntegerEvaluationMatrix.instance,
    ::Float => FloatEvaluationMatrix.instance,
    ::Complex => ComplexEvaluationMatrix.instance
}


end # Finita
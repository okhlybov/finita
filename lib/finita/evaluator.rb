require 'singleton'
require 'data_struct'
require 'finita/common'


module Finita


class Evaluator
  attr_reader :expression, :type
  def initialize(expression, type)
    # TODO merge attribute is not needed
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
    def entities; super + Collector.new.apply!(evaluator.expression).instances.collect {|o| o.code(@problem_code)} end
    def priority
      CodeBuilder::Priority::DEFAULT + 1
    end
    def initialize(evaluator, problem_code)
      @evaluator = evaluator
      @problem_code = problem_code
      @instance = "#{@problem_code.type}#{@@count += 1}"
      @ctype = Finita::NumericType[evaluator.type]
      @problem_code.defines << :FINITA_COMPLEX if evaluator.type == Complex
      super('FinitaEvaluator')
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
          return #{CEmitter.new.emit!(evaluator.expression)};
        }
      $
    end
  end # Code
end # Evaluator


class IntegerArrayCode < DataStruct::Array
  include Singleton
  def initialize
    super('FinitaIntegerArray', 'int')
  end
end # IntegerArrayCode


class IntegerListCode < DataStruct::List
  include Singleton
  def initialize
    super('FinitaIntegerList', 'int', 'FinitaIntegerComparator')
  end
  def write_intf(stream)
    stream << %$
      #{inline} int #{comparator}(int lt, int rt) {
        return lt == rt;
      }
    $
    super
  end
end # IntegerListCode


class NodeCode < DataStruct::Code
  include Singleton
  def initialize
    super('FinitaNode')
  end
  def write_intf(stream)
    stream << %$
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


class FunctionListCode < DataStruct::List
  include Singleton
  def initialize
    super('FinitaFunctionList', 'FinitaFunctionPtr', 'FinitaFunctionComparator')
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


class FunctionListArrayCode < DataStruct::Array
  include Singleton
  attr_reader :list
  def entities; super + [list] end
  def initialize
    @list = FunctionListCode.instance
    super('FinitaFunctionListArray', "#{list.type}*")
  end
end # FuncListArrayCode


class FunctionNodeMapCode < DataStruct::Map
  include Singleton
  attr_reader :key, :list
  def entities; super + [key, list] end
  def initialize
    @list = FunctionListCode.instance
    @key = NodeCode.instance
    super('FinitaFunctionNodeMap', key.type, "#{list.type}*", key.hasher, key.comparator)
  end
end # FuncNodeMapCode


class FunctionNodeCoordMapCode < DataStruct::Map
  include Singleton
  attr_reader :key, :list
  def entities; super + [key, list] end
  def initialize
    @list = FunctionListCode.instance
    @key = NodeCoordCode.instance
    super('FinitaFunctionNodeCoordMap', key.type, "#{list.type}*", key.hasher, key.comparator)
  end
end # FuncNodeMapCode


class AbstractFunctionPtrCode < CodeBuilder::Code
  attr_reader :type
  def initialize(type)
    @type = "Finita#{type}FunctionPtr"
    @return = NumericType[type]
  end
  def write_intf(stream)
    stream << %$typedef #{@return} (*#{@type})(int,int,int);$
  end
end # AbstractFunctionPtrCode


class IntegerFunctionPtrCode < AbstractFunctionPtrCode
  include Singleton
  def initialize
    super(Integer)
  end
end # IntegerFunctionPtrCode


class FloatFunctionPtrCode < AbstractFunctionPtrCode
  include Singleton
  def initialize
    super(Float)
  end
end # FloatFunctionPtrCode


class ComplexFunctionPtrCode < AbstractFunctionPtrCode
  include Singleton
  def initialize
    super(Complex)
  end
end # ComplexFunctionPtrCode


FunctionPtrCode = {
    Integer => IntegerFunctionPtrCode.instance,
    Float => FloatFunctionPtrCode.instance,
    Complex => ComplexFunctionPtrCode.instance
}


class AbstractMatrixEntryCode < DataStruct::Structure
  attr_reader :returnType
  def entities; super + [@fp, @node, @key, @list] end
  def initialize(type, element_type, return_type)
    super(type, element_type.type)
    @fp = element_type
    @node = NodeCode.instance
    @key = NodeCoordCode.instance
    @list = FunctionListCode.instance
    @returnType = return_type
  end
  def write_intf(stream)
    stream << %$
      typedef struct #{type} #{type};
      struct #{type} {
        #{@key.type} coord;
        #{@list.type} list;
      };
      #{type}* #{new}(#{@node.type}, #{@node.type});
      void #{ctor}(#{type}*, #{@node.type}, #{@node.type});
      void #{merge}(#{type}*, #{elementType});
      #{returnType} #{evaluate}(#{type}*);
      #{inline} #{@node.type} #{row}(#{type}* self) {
        #{assert}(self);
        return self->coord.row;
      }
      #{inline} #{@node.type} #{column}(#{type}* self) {
        #{assert}(self);
        return self->coord.column;
      }
      #{inline} size_t #{hasher}(#{type}* self) {
        #{assert}(self);
        return #{@key.hasher}(self->coord);
      }
      #{inline} int #{comparator}(#{type}* lt, #{type}* rt) {
        #{assert}(lt);
        #{assert}(rt);
        return #{@key.comparator}(lt->coord, rt->coord);
      }
    $
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(#{type}* self, #{@node.type} row, #{@node.type} column) {
        self->coord = #{@key.new}(row, column);
        #{@list.ctor}(&self->list);
      }
      #{type}* #{new}(#{@node.type} row, #{@node.type} column) {
        #{type}* result = (#{type}*) #{malloc}(sizeof(#{type})); #{assert}(result);
        #{ctor}(result, row, column);
        return result;
      }
      void #{merge}(#{type}* self, #{elementType} fp) {
        #{@list.append}(&self->list, (#{@list.elementType})fp);  
      }
      #{returnType} #{evaluate}(#{type}* self) {
        #{@list.it} it;
        #{returnType} result = 0;
        int x = self->coord.column.x, y = self->coord.column.y, z = self->coord.column.z;
        #{@list.itCtor}(&it, &self->list);
        while(#{@list.itHasNext}(&it)) result += ((#{elementType})#{@list.itNext}(&it))(x, y, z);
        return result;
      }
    $
  end
end # AbstractMatrixEntryCode


class IntegerMatrixEntryCode < AbstractMatrixEntryCode
  include Singleton
  def initialize
    super('FinitaIntegerMatrixEntry', FunctionPtrCode[Integer], NumericType[Integer])
  end
end # IntegerMatrixEntryCode


class FloatMatrixEntryCode < AbstractMatrixEntryCode
  include Singleton
  def initialize
    super('FinitaFloatMatrixEntry', FunctionPtrCode[Float], NumericType[Float])
  end
end # FloatMatrixEntryCode


class ComplexMatrixEntryCode < AbstractMatrixEntryCode
  include Singleton
  def initialize
    super('FinitaComplexMatrixEntry', FunctionPtrCode[Complex], NumericType[Complex])
  end
end # ComplexMatrixEntryCode


MatrixEntryCode = {
    Integer => IntegerMatrixEntryCode.instance,
    Float => FloatMatrixEntryCode.instance,
    Complex => ComplexMatrixEntryCode.instance
}


class AbstractVectorEntryCode < DataStruct::Structure
  attr_reader :returnType
  def entities; super + [@fp, @node, @list] end
  def initialize(type, element_type, return_type)
    super(type, element_type.type)
    @fp = element_type
    @node = NodeCode.instance
    @list = FunctionListCode.instance
    @returnType = return_type
  end
  def write_intf(stream)
    stream << %$
      typedef struct #{type} #{type};
      struct #{type} {
        #{@node.type} node;
        #{@list.type} list;
      };
      #{type}* #{new}(#{@node.type});
      void #{ctor}(#{type}*, #{@node.type});
      void #{merge}(#{type}*, #{elementType});
      #{returnType} #{evaluate}(#{type}*);
      #{inline} #{@node.type} #{node}(#{type}* self) {
        #{assert}(self);
        return self->node;
      }
      #{inline} size_t #{hasher}(#{type}* self) {
        return #{@node.hasher}(self->node);
      }
      #{inline} int #{comparator}(#{type}* lt, #{type}* rt) {
        return #{@node.comparator}(lt->node, rt->node);
      }
    $
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(#{type}* self, #{@node.type} node) {
        self->node = node;
        #{@list.ctor}(&self->list);
      }
      #{type}* #{new}(#{@node.type} node) {
        #{type}* result = (#{type}*) #{malloc}(sizeof(#{type})); #{assert}(result);
        #{ctor}(result, node);
        return result;
      }
      void #{merge}(#{type}* self, #{elementType} fp) {
        #{@list.append}(&self->list, (#{@list.elementType})fp);  
      }
      #{returnType} #{evaluate}(#{type}* self) {
        #{@list.it} it;
        #{returnType} result = 0;
        int x = self->node.x, y = self->node.y, z = self->node.z;
        #{@list.itCtor}(&it, &self->list);
        while(#{@list.itHasNext}(&it)) result += ((#{elementType})#{@list.itNext}(&it))(x, y, z);
        return result;
      }
    $
  end
end # AbstractVectorEntryCode


class IntegerVectorEntryCode < AbstractVectorEntryCode
  include Singleton
  def initialize
    super('FinitaIntegerVectorEntry', FunctionPtrCode[Integer], NumericType[Integer])
  end
end # IntegerVectorEntryCode


class FloatVectorEntryCode < AbstractVectorEntryCode
  include Singleton
  def initialize
    super('FinitaFloatVectorEntry', FunctionPtrCode[Float], NumericType[Float])
  end
end # FloatVectorEntryCode


class ComplexVectorEntryCode < AbstractVectorEntryCode
  include Singleton
  def initialize
    super('FinitaComplexVectorEntry', FunctionPtrCode[Complex], NumericType[Complex])
  end
end # ComplexVectorEntryCode


VectorEntryCode = {
    Integer => IntegerVectorEntryCode.instance,
    Float => FloatVectorEntryCode.instance,
    Complex => ComplexVectorEntryCode.instance
}


class AbstractEntryArrayCode < DataStruct::Array
  attr_reader :returnType
  def entities; super + [@element] end
  def initialize(type, element, return_type)
    super(type, "#{element.type}*")
    @element = element
    @returnType = return_type
  end
end # AbstractEntryArrayCode


class IntegerMatrixArrayCode < AbstractEntryArrayCode
  include Singleton
  def initialize
    super('FinitaIntegerMatrixArray', MatrixEntryCode[Integer], NumericType[Integer])
  end
end # IntegerMatrixArrayCode


class FloatMatrixArrayCode < AbstractEntryArrayCode
  include Singleton
  def initialize
    super('FinitaFloatMatrixArray', MatrixEntryCode[Float], NumericType[Float])
  end
end # FloatMatrixArrayCode


class ComplexMatrixArrayCode < AbstractEntryArrayCode
  include Singleton
  def initialize
    super('FinitaComplexMatrixArray', MatrixEntryCode[Complex], NumericType[Complex])
  end
end # ComplexMatrixArrayCode


MatrixArrayCode = {
    Integer => IntegerMatrixArrayCode.instance,
    Float => FloatMatrixArrayCode.instance,
    Complex => ComplexMatrixArrayCode.instance
}


class IntegerVectorArrayCode < AbstractEntryArrayCode
  include Singleton
  def initialize
    super('FinitaIntegerVectorArray', VectorEntryCode[Integer], NumericType[Integer])
  end
end # IntegerVectorArrayCode


class FloatVectorArrayCode < AbstractEntryArrayCode
  include Singleton
  def initialize
    super('FinitaFloatVectorArray', VectorEntryCode[Float], NumericType[Float])
  end
end # FloatVectorArrayCode


class ComplexVectorArrayCode < AbstractEntryArrayCode
  include Singleton
  def initialize
    super('FinitaComplexVectorArray', VectorEntryCode[Complex], NumericType[Complex])
  end
end # ComplexVectorArrayCode


VectorArrayCode = {
    Integer => IntegerVectorArrayCode.instance,
    Float => FloatVectorArrayCode.instance,
    Complex => ComplexVectorArrayCode.instance
}


class AbstractMatrixCode < DataStruct::Set
  attr_reader :returnType
  def entities; super + [@node, @element, @array] end
  def initialize(type, numeric_type)
    @node = NodeCode.instance
    @element = MatrixEntryCode[numeric_type]
    @array = MatrixArrayCode[numeric_type]
    @returnType = NumericType[numeric_type]
    super(type, "#{@element.type}*", @element.hasher, @element.comparator)
  end
  def write_intf(stream)
    super
    stream << %$
      void #{merge}(#{type}*, #{@node.type}, #{@node.type}, #{@element.elementType});
      #{returnType} #{evaluate}(#{type}*, #{@node.type}, #{@node.type});
      void #{linearize}(#{type}*, #{@array.type}*);
    $
  end
  def write_defs(stream)
    super
    # In the code below it is assumed that element constructor does not allocate memory
    # otherwise memory leak will occur since no destructor is ever called
    stream << %$
      void #{merge}(#{type}* self, #{@node.type} row, #{@node.type} column, #{@element.elementType} fp) {
        #{@element.type} element, *element_ptr;
        #{assert}(self);
        #{@element.ctor}(&element, row, column);
        if(#{contains}(self, &element)) {
          element_ptr = #{get}(self, &element);
        } else {
          #{put}(self, element_ptr = #{@element.new}(row, column));
        }
        #{@element.merge}(element_ptr, fp);
      }
      #{returnType} #{evaluate}(#{type}* self, #{@node.type} row, #{@node.type} column) {
        #{@element.type} element;
        #{assert}(self);
        #{@element.ctor}(&element, row, column);
        #{assert}(#{contains}(self, &element));
        return #{@element.evaluate}(#{get}(self, &element));
      }
      void #{linearize}(#{type}* self, #{@array.type}* array) {
        #{it} it;
        size_t index = 0;
        #{@array.ctor}(array, #{size}(self));
        #{itCtor}(&it, self);
        while(#{itHasNext}(&it)) {
         #{@array.set}(array, index++, #{itNext}(&it));
        }
      }
    $
  end
end # AbstractMatrixCode


class IntegerMatrixCode < AbstractMatrixCode
  include Singleton
  def initialize
    super('FinitaIntegerMatrix', Integer)
  end
end # IntegerMatrixCode


class FloatMatrixCode < AbstractMatrixCode
  include Singleton
  def initialize
    super('FinitaFloatMatrix', Float)
  end
end # FloatMatrixCode


class ComplexMatrixCode < AbstractMatrixCode
  include Singleton
  def initialize
    super('FinitaComplexMatrix', Complex)
  end
end # ComplexMatrixCode


MatrixCode = {
    Integer => IntegerMatrixCode.instance,
    Float => FloatMatrixCode.instance,
    Complex => ComplexMatrixCode.instance
}


class AbstractVectorCode < DataStruct::Set
  attr_reader :returnType
  def entities; super + [@node, @element, @array] end
  def initialize(type, numeric_type)
    @node = NodeCode.instance
    @element = VectorEntryCode[numeric_type]
    @array = VectorArrayCode[numeric_type]
    @returnType = NumericType[numeric_type]
    super(type, "#{@element.type}*", @element.hasher, @element.comparator)
  end
  def write_intf(stream)
    super
    stream << %$
      void #{merge}(#{type}*, #{@node.type}, #{@element.elementType});
      #{returnType} #{evaluate}(#{type}*, #{@node.type});
      void #{linearize}(#{type}*, #{@array.type}*);
    $
  end
  def write_defs(stream)
    super
    # In the code below it is assumed that element constructor does not allocate memory
    # otherwise memory leak will occur since no destructor is called
    stream << %$
      void #{merge}(#{type}* self, #{@node.type} node, #{@element.elementType} fp) {
        #{@element.type} element, *element_ptr;
        #{assert}(self);
        #{@element.ctor}(&element, node);
        if(#{contains}(self, &element)) {
          element_ptr = #{get}(self, &element);
        } else {
          #{put}(self, element_ptr = #{@element.new}(node));
        }
        #{@element.merge}(element_ptr, fp);
      }
      #{returnType} #{evaluate}(#{type}* self, #{@node.type} node) {
        #{@element.type} element;
        #{assert}(self);
        #{@element.ctor}(&element, node);
        #{assert}(#{contains}(self, &element));
        return #{@element.evaluate}(#{get}(self, &element));
      }
      void #{linearize}(#{type}* self, #{@array.type}* array) {
        #{it} it;
        size_t index = 0;
        #{@array.ctor}(array, #{size}(self));
        #{itCtor}(&it, self);
        while(#{itHasNext}(&it)) {
         #{@array.set}(array, index++, #{itNext}(&it));
        }
      }
    $
  end
end # AbstractVectorCode


class IntegerVectorCode < AbstractVectorCode
  include Singleton
  def initialize
    super('FinitaIntegerVector', Integer)
  end
end # IntegerVectorCode


class FloatVectorCode < AbstractVectorCode
  include Singleton
  def initialize
    super('FinitaFloatVector', Float)
  end
end # FloatVectorCode


class ComplexVectorCode < AbstractVectorCode
  include Singleton
  def initialize
    super('FinitaComplexVector', Complex)
  end
end # ComplexVectorCode


VectorCode = {
    Integer => IntegerVectorCode.instance,
    Float => FloatVectorCode.instance,
    Complex => ComplexVectorCode.instance
}


end # Finita
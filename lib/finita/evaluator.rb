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
  def integer?
    type == Integer
  end
  def float?
    type == Float
  end
  def complex?
    type == Complex
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
    attr_reader :instance
    def entities; super + Collector.new.apply!(@evaluator.expression).instances.collect {|o| o.code(@problem_code)} end
    def priority
      CodeBuilder::Priority::DEFAULT + 1
    end
    def initialize(evaluator, problem_code)
      @evaluator = evaluator
      @problem_code = problem_code
      @instance = "#{@problem_code.type}#{@@count += 1}"
      @c_type = CType[evaluator.type]
      @problem_code.defines << :FINITA_COMPLEX if evaluator.complex?
      super('FinitaEvaluator')
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
      stream << %$#{@c_type} #{instance}(int, int, int);$
    end
    def write_defs(stream)
      stream << %$
        FINITA_ARGSUSED
        #{@c_type} #{instance}(int x, int y, int z) {
          return #{CEmitter.new.emit!(@evaluator.expression)};
        }
      $
    end
  end # Code
end # Evaluator


def self.numeric_instances_hash(&block)
  Hash[[Integer, Float, Complex].collect {|type| [type, block.call(type)]}]
end


NumericArrayCode = numeric_instances_hash {|type| Class.new(DataStruct::Array).new("Finita#{type}Array", CType[type])}


NodeCode = Class.new(DataStruct::Code) do
  def write_intf(stream)
    stream << %$
      typedef struct {
        int field, x, y, z;
        size_t hash;
      } #{type};
      #define SIGN2LSB(x) ((abs(x) << 1) | (x < 0))
      #{inline} #{type} #{new}(int field, int x, int y, int z) {
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
      #{inline} size_t #{hasher}(#{type} node) {
        return node.hash;
      }
      #{inline} int #{comparator}(#{type} lt, #{type} rt) {
        return lt.field == rt.field && lt.x == rt.x && lt.y == rt.y && lt.z == rt.z;
      }
    $
  end
end.new('FinitaNode') # NodeCode


NodeArrayCode = Class.new(DataStruct::Array) do
  def entities; super << NodeCode end
end.new('FinitaNodeArray', NodeCode.type) # NodeArrayCode


NodeSetCode = Class.new(DataStruct::Set) do
  def entities; super << NodeCode end
end.new('FinitaNodeSet', NodeCode.type, NodeCode.hasher, NodeCode.comparator) # NodeSetCode


NodeIndexMapCode = Class.new(DataStruct::Map) do
  def entities; super << NodeCode end
end.new('FinitaNodeIndexMap', NodeCode.type, 'size_t', NodeCode.hasher, NodeCode.comparator) # NodeIndexMapCode


NodeCoordCode = Class.new(DataStruct::Code) do
  def entities; super << NodeCode end
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
        result.hash = FinitaHashMix(#{NodeCode.hasher}(row) ^ #{NodeCode.hasher}(column));
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
end.new('FinitaNodeCoord') # NodeCoordCode


FunctionListCode = Class.new(DataStruct::List) do
  def write_intf(stream)
    stream << %$
      typedef void (*#{elementType})(void);
      #{inline} int #{comparator}(#{elementType} lt, #{elementType} rt) {
        return lt == rt;
      }
    $
    super
  end
end.new('FinitaFunctionList', 'FinitaFunctionPtr', 'FinitaFunctionComparator') # FuncListCode


FunctionPtrCode = numeric_instances_hash do |type|
  Class.new(CodeBuilder::Code) do
    attr_reader :type
    def initialize(type)
      @type = "Finita#{type}FunctionPtr"
      @c_type = CType[type]
    end
    def write_intf(stream)
      stream << %$typedef #{@c_type} (*#{@type})(int,int,int);$
    end
  end.new(type)
end # FunctionPtrCode


MatrixEntryCode = numeric_instances_hash do |type|
  Class.new(DataStruct::Structure) do
    attr_reader :returnType
    def entities; super + [@fp, @node, @key, @list] end
    def initialize(type, element_type, return_type)
      super(type, element_type.type)
      @fp = element_type
      @node = NodeCode
      @key = NodeCoordCode
      @list = FunctionListCode
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
  end.new("Finita#{type}MatrixEntry", FunctionPtrCode[type], CType[type])
end # MatrixEntryCode


VectorEntryCode = numeric_instances_hash do |type|
  Class.new(DataStruct::Structure) do
    attr_reader :returnType
    def entities; super + [@fp, @node, @list] end
    def initialize(type, element_type, return_type)
      super(type, element_type.type)
      @fp = element_type
      @node = NodeCode
      @list = FunctionListCode
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
  end.new("Finita#{type}VectorEntry", FunctionPtrCode[type], CType[type])
end # VectorEntryCode


MatrixArrayCode = numeric_instances_hash do |type|
  Class.new(DataStruct::Array) do
    attr_reader :returnType
    def entities; super + [@element] end
    def initialize(type, element, return_type)
      super(type, "#{element.type}*")
      @element = element
      @returnType = return_type
    end
  end.new("Finita#{type}MatrixArray", MatrixEntryCode[type], CType[type])
end # MatrixArrayCode


VectorArrayCode = numeric_instances_hash do |type|
  Class.new(DataStruct::Array) do
    attr_reader :returnType
    def entities; super + [@element] end
    def initialize(type, element, return_type)
      super(type, "#{element.type}*")
      @element = element
      @returnType = return_type
    end
  end.new("Finita#{type}VectorArray", VectorEntryCode[type], CType[type])
end # VectorArrayCode


MatrixCode = numeric_instances_hash do |type|
  Class.new(DataStruct::Set) do
    attr_reader :returnType
    def entities; super + [@node, @element, @array] end
    def initialize(type, numeric_type)
      @node = NodeCode
      @element = MatrixEntryCode[numeric_type]
      @array = MatrixArrayCode[numeric_type]
      @returnType = CType[numeric_type]
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
  end.new("Finita#{type}Matrix", type)
end # MatrixCode


VectorCode = numeric_instances_hash do |type|
  Class.new(DataStruct::Set) do
    attr_reader :returnType
    def entities; super + [@node, @element, @array] end
    def initialize(type, numeric_type)
      @node = NodeCode
      @element = VectorEntryCode[numeric_type]
      @array = VectorArrayCode[numeric_type]
      @returnType = CType[numeric_type]
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
  end.new("Finita#{type}Vector", type)
end # VectorCode


end # Finita
require 'code_builder'
require 'data_struct'
require 'finita/common'
require 'finita/mapper'
require 'finita/environment'


module Finita


module Generator
  Scalar = {Integer=>'int', Float=>'double', Complex=>'_Complex double'}
end # Generator


class CustomFunctionCode < FunctionTemplate
  def initialize(gtor, name, args, result, write_method, reverse, visible = true)
    super(name, args, result, visible)
    @gtor = gtor
    @write_method = write_method
    @reverse = reverse
  end
  def write_body(stream)
    CodeBuilder.priority_sort(Set.new(@gtor.entities), @reverse).select! {|e| e.respond_to?(@write_method)}.each do |e|
      e.send(@write_method, stream)
    end
  end
end # CustomFunctionCode


class NodeCode < StaticCodeTemplate
  def write_intf(stream)
    stream << %$
      typedef struct {
        unsigned int field;
        int x, y, z;
      } FinitaNode;
      FinitaNode FinitaNodeNew(int, int, int, int);
      size_t FinitaNodeHash(FinitaNode);
      int FinitaNodeCompare(FinitaNode, FinitaNode);
      void FinitaNodeLog(FinitaNode, FILE*);
    $
  end
  def write_defs(stream)
    stream << %$
      #define MOVE_SIGN(x) ((x < 0) | (abs(x) << 1))
      size_t FinitaNodeHash(FinitaNode node) {
        /* abs(x|y|z) < 2^9 is implied; extra bit is reserved for the sign */
        size_t hash = (((MOVE_SIGN(node.x) & 0x3FF) | ((MOVE_SIGN(node.y) & 0x3FF) << 10) | ((MOVE_SIGN(node.z) & 0x3FF) << 20)) ^ (node.field << 30));
        /* Thomas Wang's mixing algorithm */
        hash = (hash ^ 61) ^ (hash >> 16);
        hash = hash + (hash << 3);
        hash = hash ^ (hash >> 4);
        hash = hash * 0x27d4eb2d;
        hash = hash ^ (hash >> 15);
        return hash;
      }
      int FinitaNodeCompare(FinitaNode lt, FinitaNode rt) {
        return lt.field == rt.field && lt.x == rt.x && lt.y == rt.y && lt.z == rt.z;
      }
      FinitaNode FinitaNodeNew(int field, int x, int y, int z) {
        #if __STDC_VERSION__ >= 199901L
          FinitaNode node = {field, x, y, z};
        #else
          FinitaNode node;
          node.field = field;
          node.x = x;
          node.y = y;
          node.z = z;
        #endif
        FINITA_ASSERT(node.field >= 0);
        return node;
      }
      void FinitaNodeLog(FinitaNode node, FILE* out) {
        fprintf(out, "{field=%d x=%d y=%d z=%d}", node.field, node.x, node.y, node.z);
      }
    $
  end
end # NodeCode


class NodeSetCode < SetAdapter
  include Singleton
  def entities; super + [NodeCode.instance] end
  def initialize
    super('FinitaNodeSet', 'FinitaNode', 'FinitaNodeHash', 'FinitaNodeCompare')
  end
end # NodeSetCode


class NodeMapCode < MapAdapter
  include Singleton
  def entities; super + [NodeCode.instance] end
  def initialize
    super('FinitaNodeMap', 'FinitaNode', 'int', 'FinitaNodeHash', 'FinitaNodeCompare')
  end
end # NodeMapCode


class FuncListCode < ListAdapter
  include Singleton
  attr_reader :scalar_type
  def initialize(type, scalar, func_type)
    @scalar_type = Generator::Scalar[scalar]
    super(type, func_type, "#{type}Compare")
  end
  def write_intf(stream)
    stream << %$
      typedef #{scalar_type} (*#{element_type})(int, int, int);
    $
    super
  end
  def write_defs(stream)
    stream << %$
      int #{comparator}(#{element_type} lt, #{element_type} rt) {
        return lt == rt;
      }
    $
    super
  end
end # FuncListCode


class IntegerFuncListCode < FuncListCode
  def initialize
    super('FinitaIntegerFuncList', Integer, 'FinitaIntegerFunc')
  end
end # IntegerFuncListCode


class FloatFuncListCode < FuncListCode
  def initialize
    super('FinitaFloatFuncList', Float, 'FinitaFloatFunc')
  end
end # FloatFuncListCode


class ComplexFuncListCode < FuncListCode
  def initialize
    super('FinitaComplexFuncList', Complex, 'FinitaComplexFunc')
  end
end # ComplexFuncListCode


module FuncList
  Code = {Integer=>IntegerFuncListCode.instance, Float=>FloatFuncListCode.instance, Complex=>ComplexFuncListCode.instance}
end # FuncList


class FuncMatrixCode < MapAdapter
  include Singleton
  class StaticCode < StaticCodeTemplate
    def write_intf(stream)
      stream << %$
        typedef struct {
          FinitaNode row, column;
        } FinitaMatrixKey;
      $
    end
    def write_defs(stream)
      stream << %$
        size_t FinitaMatrixKeyHash(FinitaMatrixKey key) {
          FinitaNode delta = {key.column.field, key.row.x-key.column.x, key.row.y-key.column.y, key.row.z-key.column.z};
          return FinitaNodeHash(key.row) ^ (FinitaNodeHash(delta));
        }
        int FinitaMatrixKeyCompare(FinitaMatrixKey lt, FinitaMatrixKey rt) {
          return FinitaNodeCompare(lt.row, rt.row) && FinitaNodeCompare(lt.column, rt.column);
        }
      $
    end
  end # StaticCode
  def entities; super + [StaticCode.instance, NodeCode.instance, func_list_code] end
  attr_reader :func_list_code
  def merge; "#{type}Merge" end
  def at; "#{type}At" end
  def initialize(type, scalar)
    @func_list_code = FuncList::Code[scalar]
    super(type, 'FinitaMatrixKey', "#{func_list_code.type}*", 'FinitaMatrixKeyHash', 'FinitaMatrixKeyCompare')
  end
  def write_intf(stream)
    super
    stream << %$
      void #{merge}(#{type}*, FinitaNode, FinitaNode, #{func_list_code.element_type});
      #{func_list_code.type}* #{at}(#{type}*, FinitaNode, FinitaNode);
    $
  end
  def write_defs(stream)
    super
    stream << %$
      void #{merge}(#{type}* self, FinitaNode row, FinitaNode column, #{func_list_code.element_type} element) {
        FinitaMatrixKey key;
        key.row = row; key.column = column;
        if(#{contains_key}(self, key)) {
          #{func_list_code.append}(#{get}(self, key), element);
        } else {
          #{func_list_code.type}* list = #{func_list_code.new}();
          #{func_list_code.append}(list, element);
          #{put}(self, key, list);
        }
      }
      #{func_list_code.type}* #{at}(#{type}* self, FinitaNode row, FinitaNode column) {
        FinitaMatrixKey key;
        key.row = row; key.column = column;
        return #{get}(self, key);
      }
    $
  end
end # FuncMatrixCode


class IntegerFuncMatrixCode < FuncMatrixCode
  def initialize
    super('FinitaIntegerFuncMatrix', Integer)
  end
end # IntegerFuncMatrixCode


class FloatFuncMatrixCode < FuncMatrixCode
  def initialize
    super('FinitaFloatFuncMatrix', Float)
  end
end # FloatFuncMatrixCode


class ComplexFuncMatrixCode < FuncMatrixCode
  def initialize
    super('FinitaComplexFuncMatrix', Complex)
  end
end # ComplexFuncMatrixCode


module FuncMatrix
  Code = {Integer=>IntegerFuncMatrixCode.instance, Float=>FloatFuncMatrixCode.instance, Complex=>ComplexFuncMatrixCode.instance}
end # FuncMatrix


class FuncVectorCode < MapAdapter
  include Singleton
  def entities; super + [NodeCode.instance, func_list_code] end
  attr_reader :func_list_code
  def merge; "#{type}Merge" end
  def at; "#{type}At" end
  def initialize(type, scalar)
    @func_list_code = FuncList::Code[scalar]
    super(type, 'FinitaNode', "#{func_list_code.type}*", 'FinitaNodeHash', 'FinitaNodeCompare')
  end
  def write_intf(stream)
    super
    stream << %$
      void #{merge}(#{type}*, FinitaNode, #{func_list_code.element_type});
      #define #{at} #{get}
    $
  end
  def write_defs(stream)
    super
    stream << %$
      void #{merge}(#{type}* self, FinitaNode row, #{func_list_code.element_type} element) {
        if(#{contains_key}(self, row)) {
          #{func_list_code.append}(#{get}(self, row), element);
        } else {
          #{func_list_code.type}* list = #{func_list_code.new}();
          #{func_list_code.append}(list, element);
          #{put}(self, row, list);
        }
      }
    $
  end
end # FuncVectorCode


class IntegerFuncVectorCode < FuncVectorCode
  def initialize
    super('FinitaIntegerFuncVector', Integer)
  end
end # IntegerFuncVectorCode


class FloatFuncVectorCode < FuncVectorCode
  def initialize
    super('FinitaFloatFuncVector', Float)
  end
end # FloatFuncVectorCode


class ComplexFuncVectorCode < FuncVectorCode
  def initialize
    super('FinitaComplexFuncVector', Complex)
  end
end # ComplexFuncVectorCode


module FuncVector
  Code = {Integer=>IntegerFuncVectorCode.instance, Float=>FloatFuncVectorCode.instance, Complex=>ComplexFuncVectorCode.instance}
end # FuncVector


end # Finita


module Finita::Generator


# Class which emits C code for the given problem.
class Default

  class Code < Finita::BoundCodeTemplate
    def entities; super + gtor.environments.collect {|env| env.static_code} end
    def initialize(gtor)
      super({:gtor=>gtor}, gtor)
    end
    def write_intf(stream)
      stream << %$
          #include <math.h>
          #include <malloc.h>
          #include <string.h>
          #include <stdio.h>
          #ifdef FINITA_COMPLEX
            #include <complex.h>
          #endif
          #if defined _MSC_VER || __PGI
            #define __func__ __FUNCTION__
          #endif
          #define FINITA_FAILURE(msg) FinitaFailure(__func__, __FILE__, __LINE__, msg);
          void FinitaFailure(const char*, const char*, int, const char*);
          #ifndef NDEBUG
              #define FINITA_ASSERT(test) if(!(test)) FinitaAssert(__func__, __FILE__, __LINE__, #test);
              void FinitaAssert(const char*, const char*, int, const char*);
          #else
              #define FINITA_ASSERT(test)
          #endif
          #define FINITA_MALLOC(size) malloc(size)
          #define FINITA_CALLOC(count, size) calloc(count, size)
          #define FINITA_FREE(ptr) free(ptr)
          #ifdef FINITA_MPI
            extern int FinitaMPIRank;
            #define FINITA_HEAD if(!FinitaMPIRank)
            #define FINITA_NHEAD if(FinitaMPIRank)
          #else
            #define FINITA_HEAD if(1)
            #define FINITA_NHEAD if(0)
          #endif
      $
    end
    def write_defs(stream)
      stream << %$
          #include <stdio.h>
          extern void FinitaAbort(int); /* To be defined elsewhere */
          void FinitaFailure(const char* func, const char* file, int line, const char* msg) {
              #ifdef FINITA_MPI
                fprintf(stderr, "\\n[%d] Finita ERROR in %s(), %s:%d: %s\\n", FinitaMPIRank, func, file, line, msg);
              #else
                fprintf(stderr, "\\nFinita ERROR in %s(), %s:%d: %s\\n", func, file, line, msg);
              #endif
              FinitaAbort(EXIT_FAILURE);
          }
          #ifndef NDEBUG
          #if defined _MSC_VER || __PGI
            #define FINITA_SNPRINTF sprintf_s
          #else
            #define FINITA_SNPRINTF snprintf
          #endif
          void FinitaAssert(const char* func, const char* file, int line, const char* test) {
              char msg[1024];
              FINITA_SNPRINTF(msg, 1024, "assertion %s failed", test);
              FinitaFailure(func, file, line, msg);
              FinitaAbort(EXIT_FAILURE);
          }
          #endif
      $
    end
  end # Code

  # Return problem object this generator is bound to.
  attr_reader :problem

  # Attach an entity if there is no other entity which have already been attached, that is considered equal to this one.
  # Returns an entity which is actually memorized.
  def <<(entity)
    @entities.has_key?(entity) ? @entities[entity] : @entities[entity] = entity
  end

  # Return code entity associated with specified object.
  def [](obj)
    result = @objects[obj]
    raise "#{obj} is unknown to the generator" if result.nil?
    result
  end

  # Return true is the object has already been registered and false otherwise.
  def bound?(obj)
    @objects.has_key?(obj)
  end

  # Attach code entity bound to the object specified.
  # Returns an entity which is actually memorized (see Generator#<<).
  def []=(obj, entity)
    @objects[obj] = self << entity
  end

  # Return a view of all code entities attached to this generator.
  def entities
    @entities.keys
  end

  attr_reader :environments, :defines

  def initialize
    @environments = Set.new
    if block_given?
      yield(self)
    end
  end

  # Generate source code for the problem.
  def generate!(problem)
    @problem = problem
    @entities = Hash.new
    @objects = Hash.new
    # A few definitions are to be placed in the header before anything else mainly to control the code
    # in static code entities which can not be parametrized in any other way since they are singletons.
    @defines = Set.new
    Code.new(self) unless bound?(self)
    environments.each {|env| env.bind(self)}
    problem.bind(self)
    @module = new_module
    entities.each {|e| @module << e}
    @module.generate
  end

  protected

  # Return new instance of module to be used by this generator.
  # This implementation returns a Finita::Module instance.
  def new_module
    Module.new(self)
  end

  class Module < CodeBuilder::Module

    class Header < CodeBuilder::Header
      def name
        @module.dotted_infix? ? "#{@module.name}.auto.h" : "#{@module.name}_auto.h"
      end
      def tag
        "__FINITA_#{@module.name.upcase}__"
      end
      def write(stream)
        stream << "\n#ifndef #{tag}\n#define #{tag}\n"
        @module.defines.each do |symbol|
          stream << "#define #{symbol}\n"
        end
        super
        stream << "\n#endif\n"
      end
      protected
      def new_stream
        File.new(name, 'wt')
      end
    end # Header

    class Source < CodeBuilder::Source
      def name
        @module.dotted_infix? ? "#{@module.name}.auto#{@index}.c" : "#{@module.name}_auto#{@index}.c"
      end
      def write(stream)
        stream << %{\n#include "#{@module.header.name}"\n}
        super
      end
      protected
      def new_stream
        File.new(name, 'wt')
      end
    end # Source

    attr_reader :name, :defines

    def dotted_infix?
      @dotted_infix
    end

    def header_name
      @header.name
    end

    def source_names
      @sources.collect {|s| s.name}
    end

    def initialize(gtor)
      super()
      @name = gtor.problem.name
      @defines = gtor.defines
      @dotted_infix = false
    end

    protected

    def new_header
      Header.new(self)
    end

    def new_source(index)
      Source.new(self, index)
    end

  end # Module


end # Default


end # Finita::Generator
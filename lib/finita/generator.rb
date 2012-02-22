require 'code_builder'
require 'data_struct'
require 'finita/common'
require 'finita/ordering'
require 'finita/environment'


module Finita


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
        int field, x, y, z;
      } FinitaNode;
      FinitaNode FinitaNodeNew(int, int, int, int);
    $
  end
  def write_defs(stream)
    stream << %$
      int FinitaNodeHash(FinitaNode node) {
        return node.field ^ (node.x<<2) ^ (node.y<<4) ^ (node.z<<6);
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
        return node;
      }
    $
  end
end # NodeCode


class NodeMapCode < MapAdapter
  include Singleton
  def entities; super + [NodeCode.instance] end
  def initialize
    super('FinitaNodeMap', 'FinitaNode', 'int', 'FinitaNodeHash', 'FinitaNodeCompare', true)
  end
end # NodeMapCode


class FpListCode < ListAdapter
  include Singleton
  def initialize
    super('FinitaFpList', 'FinitaFp', 'FinitaFpCompare', true)
  end
  def write_intf(stream)
    stream << "typedef void (*FinitaFp)(void);"
    super
  end
end # FpListCode


class FpMatrixCode < MapAdapter
  include Singleton
  def entities; super + [NodeCode.instance, FpListCode.instance] end
  def initialize
    super('FinitaFpMatrix', 'FinitaFpMatrixNode', 'FinitaFpList*', 'FinitaFpMatrixNodeHash', 'FinitaFpMatrixNodeCompare', true)
  end
  def write_intf_real(stream)
    stream << %$
      typedef struct {
        FinitaNode row_node, column_node;
      } FinitaFpMatrixNode;
    $
    super
    stream << "void FinitaFpMatrixMerge(FinitaFpMatrix*, FinitaNode, FinitaNode, FinitaFp);"
  end
  def write_defs(stream)
    stream << %$
      int FinitaFpCompare(FinitaFp lt, FinitaFp rt) {
        return lt == rt;
      }
      int FinitaFpMatrixNodeHash(FinitaFpMatrixNode node) {
        return FinitaNodeHash(node.row_node) ^ FinitaNodeHash(node.column_node);
      }
      int FinitaFpMatrixNodeCompare(FinitaFpMatrixNode lt, FinitaFpMatrixNode rt) {
        return FinitaNodeCompare(lt.row_node, rt.row_node) && FinitaNodeCompare(lt.column_node, rt.column_node);
      }
      void FinitaFpMatrixMerge(FinitaFpMatrix* self, FinitaNode row, FinitaNode column, FinitaFp fp) {
        FinitaFpMatrixNode node;
        FINITA_ASSERT(self);
        node.row_node = row; node.column_node = column;
        if(FinitaFpMatrixContainsKey(self, node)) {
          FinitaFpListAppend(FinitaFpMatrixGet(self, node), fp);
        } else {
          FinitaFpList* fps = FinitaFpListNew();
          FinitaFpListAppend(fps, fp);
          FinitaFpMatrixPut(self, node, fps);
        }
      }
    $
    super
  end
end # MatrixCode


class FpVectorCode < StaticCodeTemplate
  TAG = :FinitaFpVector
  def entities; super + [Ordering::StaticCode.instance, FpMatrixCode.instance] end
  def write_intf(stream)
    stream << %$
      typedef struct {
        FinitaFpList** linear;
        int linear_size;
      } #{TAG};
      void #{TAG}Ctor(#{TAG}*, FinitaOrdering*);
      void #{TAG}Merge(#{TAG}*, int, FinitaFp);
      FinitaFpList* #{TAG}Get(#{TAG}*, int);
    $
  end
  def write_defs(stream)
    stream << %$
      void #{TAG}Ctor(#{TAG}* self, FinitaOrdering* ordering) {
        int index;
        FINITA_ASSERT(self);
        FINITA_ASSERT(ordering);
        FINITA_ASSERT(ordering->frozen);
        self->linear_size = FinitaOrderingSize(ordering);
        self->linear = FINITA_MALLOC(self->linear_size*sizeof(FinitaFpList*)); FINITA_ASSERT(self->linear);
        for(index = 0; index < self->linear_size; ++index) {
          self->linear[index] = FinitaFpListNew();
        }
      }
      void #{TAG}Merge(#{TAG}* self, int index, FinitaFp fp) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(fp);
        FINITA_ASSERT(0 <= index && index < self->linear_size);
        FinitaFpListAppend(self->linear[index], fp);
      }
      FinitaFpList* #{TAG}Get(#{TAG}* self, int index) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(0 <= index && index < self->linear_size);
        return self->linear[index];
      }
    $
  end
end # FpVectorCode


end # Finita


module Finita::Generator


Scalar = {Integer=>'int', Float=>'double', Complex=>'_Complex double'}


# Class which emits C code for the given problem.
class Default

  class Code < Finita::BoundCodeTemplate
    def entities; super + gtor.environments.collect {|env| env.static_code} end
    def initialize(gtor)
      super({:gtor=>gtor}, gtor)
    end
    def write_intf(stream)
      stream << %$
          #include <malloc.h>
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
          #ifdef FINITA_MPI
            extern int FinitaRank;
            #define FINITA_HEAD if(!FinitaRank)
            #define FINITA_NHEAD if(FinitaRank)
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
          #ifdef FINITA_MPI
            int FinitaRank;
          #endif
          void FinitaFailure(const char* func, const char* file, int line, const char* msg) {
              #ifdef FINITA_MPI
                fprintf(stderr, "\\n[%d] Finita ERROR in %s(), %s:%d: %s\\n", FinitaRank, func, file, line, msg);
              #else
                fprintf(stderr, "\\nFinita ERROR in %s(), %s:%d: %s\\n", func, file, line, msg);
              #endif
              FinitaAbort(EXIT_FAILURE);
          }
          #ifndef NDEBUG
          #if defined _MSC_VER || __PGI
            #define __SNPRINTF sprintf_s
          #else
            #define __SNPRINTF snprintf
          #endif
          void FinitaAssert(const char* func, const char* file, int line, const char* test) {
              char msg[1024];
              __SNPRINTF(msg, 1024, "assertion %s failed", test);
              FinitaFailure(func, file, line, msg);
              FinitaAbort(EXIT_FAILURE);
          }
          #undef __SNPRINTF
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
    @environments = Set.new([Environment::Serial.instance])
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

end # Default


class Module < CodeBuilder::Module

  attr_reader :name, :defines

  def dotted_infix?
    @dotted_infix
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


end # Finita::Generator
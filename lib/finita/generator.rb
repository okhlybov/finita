require 'code_builder'
require 'data_struct'
require 'finita/common'
require 'finita/mapper'
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
      int FinitaNodeHash(FinitaNode);
      int FinitaNodeCompare(FinitaNode, FinitaNode);
      void FinitaNodeLog(FinitaNode, FILE*);
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
    super('FinitaNodeSet', 'FinitaNode', 'FinitaNodeHash', 'FinitaNodeCompare', true)
  end
end # NodeSetCode


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
    stream << %$
      typedef void (*FinitaFp)(void);
      int FinitaFpCompare(FinitaFp, FinitaFp);
    $
    super
  end
  def write_defs(stream)
    stream << %$
      int FinitaFpCompare(FinitaFp lt, FinitaFp rt) {
        return lt == rt;
      }
    $
    super
  end
end # FpListCode


class MatrixCode < MapAdapter
  include Singleton
  def entities; super + [NodeCode.instance, FpListCode.instance] end
  def initialize
    super('FinitaMatrix', 'FinitaMatrixKey', 'FinitaFpList*', 'FinitaMatrixKeyHash', 'FinitaMatrixKeyCompare', true)
  end
  def write_intf_real(stream)
    stream << %$
      typedef struct {
        FinitaNode row, column;
      } FinitaMatrixKey;
    $
    super
    stream << %$
      void FinitaMatrixMerge(FinitaMatrix*, FinitaNode, FinitaNode, FinitaFp);
      FinitaFpList* FinitaMatrixAt(FinitaMatrix*, FinitaNode, FinitaNode);
    $
  end
  def write_defs(stream)
    stream << %$
      int FinitaMatrixKeyHash(FinitaMatrixKey key) {
        return FinitaNodeHash(key.row) ^ FinitaNodeHash(key.column);
      }
      int FinitaMatrixKeyCompare(FinitaMatrixKey lt, FinitaMatrixKey rt) {
        return FinitaNodeCompare(lt.row, rt.row) && FinitaNodeCompare(lt.column, rt.column);
      }
      void FinitaMatrixMerge(FinitaMatrix* self, FinitaNode row, FinitaNode column, FinitaFp fp) {
        FinitaMatrixKey key;
        FINITA_ASSERT(self);
        key.row = row; key.column = column;
        if(FinitaMatrixContainsKey(self, key)) {
          FinitaFpListAppend(FinitaMatrixGet(self, key), fp);
        } else {
          FinitaFpList* fps = FinitaFpListNew();
          FinitaFpListAppend(fps, fp);
          FinitaMatrixPut(self, key, fps);
        }
      }
      FinitaFpList* FinitaMatrixAt(FinitaMatrix* self, FinitaNode row, FinitaNode column) {
        FinitaMatrixKey key;
        FINITA_ASSERT(self);
        key.row = row; key.column = column;
        return FinitaMatrixGet(self, key);
      }
    $
    super
  end
end # MatrixCode


class VectorCode < MapAdapter
  include Singleton
  def entities; super + [NodeCode.instance, FpListCode.instance] end
  def initialize
    super('FinitaVector', 'FinitaNode', 'FinitaFpList*', 'FinitaNodeHash', 'FinitaNodeCompare', true)
  end
  def write_intf_real(stream)
    super
    stream << %$
      void FinitaVectorMerge(FinitaVector*, FinitaNode, FinitaFp);
      FinitaFpList* FinitaVectorAt(FinitaVector*, FinitaNode);
    $
  end
  def write_defs(stream)
    stream << %$
      void FinitaVectorMerge(FinitaVector* self, FinitaNode row, FinitaFp fp) {
        FINITA_ASSERT(self);
        if(FinitaVectorContainsKey(self, row)) {
          FinitaFpListAppend(FinitaVectorGet(self, row), fp);
        } else {
          FinitaFpList* fps = FinitaFpListNew();
          FinitaFpListAppend(fps, fp);
          FinitaVectorPut(self, row, fps);
        }
      }
      FinitaFpList* FinitaVectorAt(FinitaVector* self, FinitaNode row) {
        FINITA_ASSERT(self);
        return FinitaVectorGet(self, row);
      }
    $
    super
  end
end # VectorCode


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
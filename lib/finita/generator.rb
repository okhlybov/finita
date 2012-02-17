require 'finita/common'
require 'code_builder'
require 'data_struct'


module Finita


class CustomFunctionCode < FunctionTemplate
  def initialize(gtor, name, args, result, write_method, visible = true)
    super(name, args, result, visible)
    @gtor = gtor
    @write_method = write_method
  end
  def write_body(stream)
    CodeBuilder.priority_sort(Set.new(@gtor.entities)).select! {|e| e.respond_to?(@write_method)}.each do |e|
      e.send(@write_method, stream)
    end
  end
end # CustomFunctionCode


class NodeMapCode < MapAdapter
  include Singleton
  def entities; super + [Finita::Generator::StaticCode.instance] end
  def initialize
    super('FinitaNodeMap', 'FinitaNode', 'int', 'FinitaNodeHash', 'FinitaNodeCompare', true)
  end
  def write_intf_real(stream)
    stream << %$
      typedef struct {
        int field, x, y, z;
      } FinitaNode;
      static FinitaNode FinitaNodeNew(int field, int x, int y, int z) {
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
    super
  end
  def write_defs(stream)
    stream << %$
      int FinitaNodeHash(FinitaNode node) {
        return node.field ^ (node.x<<2) ^ (node.y<<4) ^ (node.z<<6);
      }
      int FinitaNodeCompare(FinitaNode lt, FinitaNode rt) {
        return lt.field == rt.field && lt.x == rt.x && lt.y == rt.y && lt.z == rt.z;
      }
    $
    super
  end
end # NodeMapCode


class FpMatrixCode < MapAdapter
  include Singleton
  def entities; super + [NodeMapCode.instance] end
  def initialize
    super('FinitaFpMatrix', 'FinitaFpMatrixNode', 'FinitaFpList*', 'FinitaFpMatrixNodeHash', 'FinitaFpMatrixNodeCompare', true)
    @list = ListAdapter.new('FinitaFpList', 'FinitaFp', 'FinitaFpCompare', true)
  end
  def write_intf_real(stream)
    stream << %$
      typedef void (*FinitaFp)(void);
      typedef struct {
        FinitaNode row_node, column_node;
      } FinitaFpMatrixNode;
    $
    @list.write_intf_real(stream)
    super
    stream << "void FinitaFpMatrixMerge(FinitaFpMatrix*, FinitaNode, FinitaNode, FinitaFp);"
  end
  def write_defs(stream)
    @list.write_defs(stream)
    super
    stream << %$
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
  end
end # MatrixCode


class Module < CodeBuilder::Module

  attr_reader :name, :defines

  def initialize(name, defines)
    super()
    @name = name
    @defines = defines
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
    "#{@module.name}.auto.h"
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
    "#{@module.name}.auto#{@index}.c"
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


end # Finita


module Finita::Generator


Scalar = {Integer=>'int', Float=>'double', Complex=>'_Complex double'}


class StaticCode < Finita::StaticCodeTemplate
  def priority; CodeBuilder::Priority::MAX end
  def write_intf(stream)
    stream << %$
        #include <malloc.h>
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
        #ifdef FINITA_PARALLEL
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
        #ifdef FINITA_PARALLEL
          int FinitaRank;
        #endif
        void FinitaFailure(const char* func, const char* file, int line, const char* msg) {
            #ifdef FINITA_PARALLEL
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
end # StaticCode


# Class which emits C code for the given problem.
class Default

  # Return problem object this generator is bound to.
  attr_reader :problem

  # Attach an entity if there is no other entity which have already been attached, that is considered equal to this one.
  # Returns an entity which is actually memorized.
  def <<(entity)
    @entities.has_key?(entity) ? @entities[entity] : @entities[entity] = entity
  end

  # Return code entity associated with specified object.
  def [](obj)
    @objects[obj]
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

  # Generate source code for the problem.
  def generate!(problem)
    @problem = problem
    @entities = Hash.new
    @objects = Hash.new
    problem.bind(self)
    # A few definitions are to be placed in the header before anything else mainly to control the code
    # in static code entities which can not be parametrized in any other way since they are singletons.
    @defines = []
    @defines << :FINITA_PARALLEL if problem.parallel?
    #
    @module = new_module
    @entities.each_key {|e| @module << e}
    @module.generate
  end

  protected

  # Return new instance of module to be used by this generator.
  # This implementation returns a Finita::Module instance.
  def new_module
    Finita::Module.new(@problem.name, @defines)
  end

end # Default


end # Finita::Generator
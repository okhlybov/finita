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


class CoordSetCode < SetAdapter
  include Singleton
  def initialize
    super('FinitaCoordSet', 'FinitaCoord*', 'FinitaCoordHasher', 'FinitaCoordComparator', true)
  end
  def write_intf(stream)
    stream << %$
      typedef struct {
        int field, x, y, z;
        int index;
      } FinitaCoord;
    $
    super
  end
  def write_defs(stream)
    stream << %$
      int FinitaCoordHasher(FinitaCoord* coord) {
        return coord->field ^ (coord->x<<2) ^ (coord->y<<4) ^ (coord->z<<6);
      }
      int FinitaCoordComparator(FinitaCoord* lt, FinitaCoord* rt) {
        return lt->field == rt->field && lt->x == rt->x && lt->y == rt->y && lt->z == rt->z;
      }
    $
    super
  end
end # CoordSetCode


# Class which emits C code for the given problem.
class Generator

  Scalar = {Integer=>'int', Float=>'double', Complex=>'_Complex double'}

  class StaticCode < StaticCodeTemplate
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
      $
    end
    def write_defs(stream)
      stream << %$
          #include <stdio.h>
          extern void FinitaAbort(int); /* To be defined elsewhere */
          int FinitaRank;
          void FinitaFailure(const char* func, const char* file, int line, const char* msg) {
              fprintf(stderr, "\\n[%d] Finita ERROR in %s(), %s:%d: %s\\n", FinitaRank, func, file, line, msg);
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
    @module = new_module
    @entities.each_key {|e| @module << e}
    @module.generate
  end

  protected

  # Return new instance of module to be used by this generator.
  # This implementation returns a Finita::Module instance.
  def new_module
    Module.new(@problem.name)
  end

end # Generator


class Module < CodeBuilder::Module

  attr_reader :name

  def initialize(name)
    super()
    @name = name
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
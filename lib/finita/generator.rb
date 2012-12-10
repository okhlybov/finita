require 'singleton'
require 'code_builder'
require 'data_struct'


class DataStruct::Code
  def setup_overrides
    @overrides = {:malloc=>'FINITA_MALLOC', :calloc=>'FINITA_CALLOC', :free=>'FINITA_FREE', :assert=>'FINITA_ASSERT', :abort=>'FINITA_ABORT', :inline=>'FINITA_INLINE'}
  end
end # DataStruct::Code


module Finita::Generator


class PrologueCode < CodeBuilder::Code
  def priority; CodeBuilder::Priority::MAX end
  def initialize(defines)
    @defines = defines
  end
  def write_intf(stream)
    @defines.each {|s| stream << "#define #{s}\n"}
    stream << %$
      #include <stdlib.h>
      #include <malloc.h>

      #if defined _MSC_VER || __PGI
        #define __func__ __FUNCTION__
      #endif

      #if defined _MSC_VER
        #define FINITA_ARGSUSED __pragma(warning(disable:4100))
      #elif __STDC_VERSION__ >= 199901L && !defined __DMC__
        #define FINITA_ARGSUSED _Pragma("argsused")
      #else
        #define FINITA_ARGSUSED
      #endif

      #if defined _MSC_VER
        #define FINITA_NORETURN(x) __declspec(noreturn) x
      #elif defined __GNUC__
        #define FINITA_NORETURN(x) x __attribute__((noreturn))
      #else
        #define FINITA_NORETURN(x) x
      #endif

      #if defined _MSC_VER
        #define FINITA_INLINE __inline static
      #elif __STDC_VERSION__ >= 199901L && !defined __PGI && !defined __DMC__
        #define FINITA_INLINE inline static
      #else
        #define FINITA_INLINE static
      #endif

      #define FINITA_FAILURE(msg) FinitaFailure(__func__, __FILE__, __LINE__, msg);
      FINITA_NORETURN(void FinitaFailure(const char*, const char*, int, const char*));

      #ifndef NDEBUG
        #define FINITA_ASSERT(test) if(!(test)) FinitaAssert(__func__, __FILE__, __LINE__, #test);
        FINITA_NORETURN(void FinitaAssert(const char*, const char*, int, const char*));
      #else
        #define FINITA_ASSERT(test)
      #endif

      #define FINITA_MALLOC(size) malloc(size)
      #define FINITA_CALLOC(count, size) calloc(count, size)
      #define FINITA_FREE(ptr) free(ptr)
      #define FINITA_ABORT() FinitaAbort(EXIT_FAILURE)
      FINITA_NORETURN(void FinitaAbort(int));
      #define FINITA_OK EXIT_SUCCESS
      #define FINITA_ERROR EXIT_FAILURE

      #ifdef FINITA_COMPLEX
        #include <complex.h>
      #endif

      #ifdef FINITA_MPI
        #include <mpi.h>
        #define FINITA_HEAD if(FinitaProcessIndex == 0)
        #define FINITA_NHEAD if(FinitaProcessIndex != 0)
      #else
        #define FINITA_HEAD
        #define FINITA_NHEAD
      #endif
    $
  end
  def write_defs(stream)
    stream << %$
      #include <math.h>
      #include <stdio.h>
        void FinitaFailure(const char* func, const char* file, int line, const char* msg) {
          #ifdef FINITA_MPI
            fprintf(stderr, "\\n[%d] Finita ERROR in %s(), %s:%d: %s\\n", FinitaProcessIndex, func, file, line, msg);
          #else
            fprintf(stderr, "\\nFinita ERROR in %s(), %s:%d: %s\\n", func, file, line, msg);
          #endif
          FinitaAbort(EXIT_FAILURE);
        }
        #ifndef NDEBUG
        #if defined _MSC_VER || defined __PGI
          #define FINITA_SNPRINTF sprintf_s
        #else
          #define FINITA_SNPRINTF snprintf
        #endif
        void FinitaAssert(const char* func, const char* file, int line, const char* test) {
          char msg[1024];
          #if defined __DMC__
            sprintf(msg, "assertion %s failed", test);
          #else
            FINITA_SNPRINTF(msg, 1024, "assertion %s failed", test);
          #endif
          FinitaFailure(func, file, line, msg);
        }
        #endif
    $
  end
end # PrologueCode


class Module < CodeBuilder::Module
  attr_reader :file_prefix
  def initialize(file_prefix)
    super()
    @file_prefix = file_prefix # TODO
  end
  def new_header
    Header.new(self)
  end
  def new_source(index)
    Source.new(self, index)
  end
end # Module


class Source < CodeBuilder::Source
  attr_reader :file_name
  def initialize(m, index)
    super(m, index)
    @file_name = "#{@module.file_prefix}.auto#{index}.c"
  end
  def new_stream
    File.new(file_name, 'wt')
  end
  def write(stream)
    stream << %$
      #include "#{@module.header.file_name}"
    $
    super
    stream << "\n"
  end
end # Source


class Header < CodeBuilder::Header
  attr_reader :file_name, :header_tag
  def initialize(m)
    super(m)
    @file_name = "#{@module.file_prefix}.auto.h"
    @header_tag = @module.file_prefix.upcase + "_H"
  end
  def new_stream
    File.new(file_name, 'wt')
  end
  def write(stream)
    stream << %$
      #ifndef #{header_tag}
      #define #{header_tag}
    $
    super
    stream << %$
      #endif
    $
    stream << "\n"
  end
end # Header


end # Finita::Generator
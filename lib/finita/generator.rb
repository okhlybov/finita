require "autoc"


module Finita


class AutoC::Code
    def debug_code(stream, &block)
      if block_given?
        stream << %$\n#ifndef NDEBUG\n$
        yield
        stream << %$\n#endif\n$
      end
    end
end # AutoC::Code


class AutoC::Type
  alias :autoc_entities :entities
  def entities
    autoc_entities << Code::CommonCode
  end
end # AutoC::Type


class Code < AutoC::Code
  
  # @private
  # Definitions copied from AutoC::Type; waiting for possibility to import them instead should it arise in a future AutoC release
  module CommonMethods
    def assert; :FINITA_ASSERT end
    def extern; :AUTOC_EXTERN end
    def inline; :AUTOC_INLINE end
    def static; :AUTOC_STATIC end
    def malloc; :malloc end
    def calloc; :calloc end
    def abort; :abort end
    def free; :free end
  end # CommonMethods

  # @private
  CommonCode = Class.new(AutoC::Code) do
    include CommonMethods
    def entities; super << AutoC::Type::CommonCode end # WARNING implementation dependency
    def write_intf(stream)
      stream << %$
        #include <stdio.h>
        #include <stdlib.h>
        #include <malloc.h>

        #if defined(_MSC_VER) || defined(__PGI)
          #define __func__ __FUNCTION__
        #endif

        #if defined(_MSC_VER)
          #define FINITA_ARGSUSED __pragma(warning(disable:4100))
        #elif defined(__GNUC__)
          #define FINITA_ARGSUSED __attribute__((__unused__))
        #elif __STDC_VERSION__ >= 199901L && !defined(__DMC__)
          #define FINITA_ARGSUSED _Pragma("argsused")
        #else
          #define FINITA_ARGSUSED
        #endif

        #if defined(_MSC_VER)
          #define FINITA_NORETURN(x) __declspec(noreturn) x
        #elif defined(__GNUC__)
          #define FINITA_NORETURN(x) x __attribute__((noreturn))
        #else
          #define FINITA_NORETURN(x) x
        #endif

        #define FINITA_ENTER
        #define FINITA_LEAVE
        #define FINITA_RETURN(x) return x;

        #define FINITA_FAILURE(msg) FinitaFailure(__func__, __FILE__, __LINE__, msg);
        #{extern} void FinitaFailure(const char*, const char*, int, const char*);

        #ifndef NDEBUG
          #define FINITA_ASSERT(test) if(!(test)) FinitaAssert(__func__, __FILE__, __LINE__, #test);
          #{extern} void FinitaAssert(const char*, const char*, int, const char*);
        #else
          #define FINITA_ASSERT(test)
        #endif

        #ifdef FINITA_MPI
          #define FINITA_HEAD if(FinitaProcessIndex == 0)
          #define FINITA_NHEAD if(FinitaProcessIndex != 0)
        #else
          #define FINITA_HEAD if(1)
          #define FINITA_NHEAD if(0)
        #endif

        #{extern} size_t FinitaHashMix(size_t);
        #{extern} int FinitaFloatsAlmostEqual(float, float);
      $
    end
    def write_defs(stream)
      # TODO portable version of snprintf
      stream << %$
        #include <math.h>
        void FinitaFailure(const char* func, const char* file, int line, const char* msg) {
          #ifdef FINITA_MPI
            fprintf(stderr, "\\n[%d] Finita ERROR in %s(), %s:%d: %s\\n", FinitaProcessIndex, func, file, line, msg);
          #else
            fprintf(stderr, "\\nFinita ERROR in %s(), %s:%d: %s\\n", func, file, line, msg);
          #endif
          #{abort}();
        }
        #ifndef NDEBUG
          #if defined(_MSC_VER) || defined(__PGI)
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
        /*
          Thomas Wang's mixing algorithm, 32-bit version
          http://web.archive.org/web/20071223173210/http://www.concentric.net/~Ttwang/tech/inthash.htm
        */
        size_t FinitaHashMix(size_t hash) {
          FINITA_ENTER;
          hash = (hash ^ 61) ^ (hash >> 16);
          hash = hash + (hash << 3);
          hash = hash ^ (hash >> 4);
          hash = hash * 0x27d4eb2d;
          hash = hash ^ (hash >> 15);
          FINITA_RETURN(hash);
        }
        /*
          Bruce Dawson's floating-point comparison algorithm
          http://www.cygnus-software.com/papers/comparingfloats/comparingfloats.htm
        */
        #include <inttypes.h>
        int FinitaFloatsAlmostEqual(float a, float b) {
          union {float f; int32_t i;} au, bu; /* workaround for the strict aliasing rule warning */
          int result;
          FINITA_ENTER;
          #{assert}(sizeof(int32_t) == sizeof(float));
          au.f = a;
          bu.f = b;
          if(au.i < 0) au.i = 0x80000000 - au.i;
          if(bu.i < 0) bu.i = 0x80000000 - bu.i;
          result =  abs(au.i - bu.i) <= 1 ? 1 : 0;
          FINITA_RETURN(result);
        }
      $
    end
  end.new # CommonCode
  
  include CommonMethods
  
  def entities; super << CommonCode end
  
  def priority
    @priority.nil? ? @priority = super : @priority # WARNING : caching might be dangerous
  end
  
  def type; @prefix end
  
  def initialize(prefix)
    @prefix = prefix.to_s
  end
  
  def method_missing(method, *args)
    str = method.to_s
    str = str.sub(/[\!\?]$/, '') # Strip trailing ? or !
    fn = @prefix + str[0,1].capitalize + str[1..-1] # Ruby 1.8 compatible
    if args.empty?
      fn # Emit bare function name
    elsif args.size == 1 && args.first == nil
      fn + '()' # Use sole nil argument to emit function call with no arguments
    else
      fn + '(' + args.join(',') + ')' # Emit normal function call with supplied arguments
    end
  end
  
end # Code


ComplexCode = Class.new(Code) do
  def priority; AutoC::Priority::MAX end
  def write_intf(stream)
    stream << %$
      #define FINITA_COMPLEX
      #include <complex.h>
    $
  end
end.new(:FinitaComplex)


end # Finita

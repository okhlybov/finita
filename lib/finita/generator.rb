require "autoc"


module Finita


class Type < AutoC::Type
  
  # @private
  CommonCode = Class.new(AutoC::Type) do
    def initialize
      super("Finita")
    end
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
          #include <mpi.h>
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
        #include <stdio.h>
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
          http://www.concentric.net/~ttwang/tech/inthash.htm
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
        int FinitaFloatsAlmostEqual(float a, float b) {
          int ai, bi, result;
          FINITA_ENTER;
          #{assert}(sizeof(int) == 4);
          ai = *(int*)&a;
          if(ai < 0) ai = 0x80000000 - ai;
          bi = *(int*)&b;
          if (bi < 0) bi = 0x80000000 - bi;
          result =  abs(ai - bi) <= 1 ? 1 : 0;
          FINITA_RETURN(result);
        }
      $
    end
  end.new # CommonCode
  
  def entities
    super << CommonCode
  end
  
end # Type


end # Finita

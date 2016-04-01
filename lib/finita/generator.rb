require "autoc"


module Finita


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
    String = AutoC::String.new(:FinitaString)
    def entities
      super << AutoC::Type::CommonCode << String
    end
    def write_intf(stream)
      stream << %$
        #include <stdio.h>
        #include <stdlib.h>
        #include <malloc.h>

        #if defined(_MSC_VER)
          #define FINITA_ARGSUSED __pragma(warning(disable:4100))
          #define FINITA_PARAMUSED __pragma(warning(disable:4101))
        #elif defined(__GNUC__)
          #define FINITA_ARGSUSED __attribute__((__unused__))
          #define FINITA_PARAMUSED __attribute__((__unused__))
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

        #if __STDC_VERSION__ >= 199901L
          #define __FINITA_FUNC__ __func__
        #else
          #define __FINITA_FUNC__ __FUNCTION__
        #endif

        #define FINITA_FAILURE(msg) FinitaFailure(__FINITA_FUNC__, __FILE__, __LINE__, msg);
        #{extern} void FinitaFailure(const char*, const char*, int, const char*);

        #ifndef NDEBUG
          #define FINITA_ASSERT(test) if(!(test)) FinitaAssert(__FINITA_FUNC__, __FILE__, __LINE__, #test);
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
      stream << %$
        #include <math.h>
        void FinitaFailure(const char* func, const char* file, int line, const char* msg) {
          #{String.type} out;
          #{String.ctor}(&out, NULL);
          #ifdef FINITA_MPI
            #{String.pushFormat}(&out, "\\n[%d] Finita ERROR in %s(), %s:%d: %s\\n", FinitaProcessIndex, func, file, line, msg);
            fprintf(stderr, #{String.chars}(&out));
            MPI_Abort(MPI_COMM_WORLD, 1);
          #else
            #{String.pushFormat}(&out, "\\nFinita ERROR in %s(), %s:%d: %s\\n", func, file, line, msg);
            fprintf(stderr, #{String.chars}(&out));
            #{abort}();
          #endif
        }
        #ifndef NDEBUG
          void FinitaAssert(const char* func, const char* file, int line, const char* test) {
            #{String.type} out;
            #{String.ctor}(&out, NULL);
            #{String.pushFormat}(&out, "assertion %s failed", test);
            FinitaFailure(func, file, line, #{String.chars}(&out));
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
  
  # FIXME : why roll out own method instead of using the AutoC's ???
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


XYZCode = Class.new(Finita::Code) do
  def write_intf(stream)
    stream << %$
      #define FINITA_FORXYZ_BEGIN(obj) { FINITA_ENTER; \\
        size_t index; \\
        int FINITA_PARAMUSED x, y, z; \\
        for(index = 0; index < obj##_XYZ.size; ++index) { \\
          x = obj##_XYZ.nodes[index].x; y = obj##_XYZ.nodes[index].y; z = obj##_XYZ.nodes[index].z;
      #define FINITA_FORXYZ_END } FINITA_LEAVE; }
      typedef struct #{node} #{node};
      struct #{node} {int x; int y; int z;};
      typedef struct #{type} #{type};
      struct #{type} {
        #{node}* nodes;
        size_t size;
      };
      #{extern} void #{ctor}(FinitaXYZ*, size_t);
      #{extern} void #{dtor}(FinitaXYZ*);
      #{extern} void #{set}(FinitaXYZ*, size_t, int, int, int);
    $
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(FinitaXYZ* self, size_t size) {
        FINITA_ENTER;
        #{assert}(self);
        self->size = size;
        self->nodes = (FinitaXYZNode*)#{malloc}(sizeof(FinitaXYZNode)*size); #{assert}(self->nodes);
        FINITA_LEAVE;
      }
      void #{dtor}(FinitaXYZ* self) {
        FINITA_ENTER;
        #{assert}(self);
        #{free}(self->nodes);
        FINITA_LEAVE;
      }
      void #{set}(FinitaXYZ* self, size_t index, int x, int y, int z) {
        FINITA_ENTER;
        #{assert}(self);
        #{assert}(index < self->size);
        self->nodes[index].x = x;
        self->nodes[index].y = y;
        self->nodes[index].z = z;
        FINITA_LEAVE;
      }
    $
  end
end.new(:FinitaXYZ)


end # Finita

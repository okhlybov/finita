require "autoc"


module Finita


StringCode = AutoC::String.new(:FinitaString)


CallStackCode = Class.new(AutoC::List) do
  Opening = %$\n#ifndef NDEBUG\n$
  Closing = %$\n#endif\n$
  def write_intf(stream)
    stream << %$
      #ifndef NDEBUG
        #{extern} void #{dump}(void);
      #else
        #define #{dump}()
      #endif
    $
    stream << Opening
    stream << %$
      typedef struct #{element.type} #{element.type};
      struct #{element.type} {
        const char* func;
        const char* file;
        int line;
      };
      /* NOTE : fake functions, not for use! */
      #define #{element.equal}(lt, rt) 0
      #define #{element.identify}(obj) 0
    $
    super
    stream << Closing
  end
  def write_decls(stream)
    stream << Opening
    super
    stream << Closing
  end
  def write_defs(stream)
    stream << Opening
    stream << %$
      void #{dump}(void) {
        FINITA_HEAD {
          #{CallStackCode.it} it;
          #{CallStackCode.itCtor}(&it, &#{CallStackCode.trace});
          fprintf(stderr, "\\n--- stack trace start ---\\n");
          while(#{CallStackCode.itMove}(&it)) {
            #{CallStackCode.element.type} cs = #{CallStackCode.itGet}(&it);
            fprintf(stderr, "%s(), %s:%d\\n", cs.func, cs.file, cs.line);
          }
          fprintf(stderr, "---  stack trace end  ---\\n");
          fflush(stderr);
        }
      }
    $
    super
    stream << Closing
  end
end.new(:FinitaCallStack, {:type => :FinitaCallStackEntry, :equal => :FinitaCallStackEntryEqual, :identify => :FinitaCallStackEntryIdentify})


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
    def abort; :FinitaAbort end
    def free; :free end
  end # CommonMethods

  # Include into the Finita::Code descendant classes to trace heap allocations
  module AllocTrace
    def entities
      super << AllocTraceCode
    end
    def malloc; :FINITA_MALLOC_TRACE end
    def calloc; :FINITA_CALLOC_TRACE end
  end

  AllocTraceCode = Class.new(AutoC::Code) do
    def write_intf(stream)
      stream << %$
        #include <malloc.h>
        #ifndef NDEBUG
          #define FINITA_MALLOC_TRACE(size) FinitaMallocTrace(size, __FINITA_FUNC__, __FILE__, __LINE__)
          void* FinitaMallocTrace(size_t, const char*, const char*, int);
          #define FINITA_CALLOC_TRACE(count, size) FinitaCallocTrace(count, size, __FINITA_FUNC__, __FILE__, __LINE__)
          void* FinitaCallocTrace(size_t, size_t, const char*, const char*, int);
        #else
          #define FINITA_MALLOC_TRACE(size) malloc(size)
          #define FINITA_CALLOC_TRACE(count, size) malloc(count, size)
        #endif
      $
    end
    def write_defs(stream)
      stream << %$
        #ifndef NDEBUG
          #undef SZ
          #define SZ size
          #define Gb (1024*1024*1024)
          #define Mb (1024*1024)
          #define Kb (1024)
          void* FinitaMallocTrace(size_t size, const char* func, const char* file, int line) {
            char t[1024];
            char* u;
            double v;
            if(size >= Gb) {
              u = "Gb";
              v = (double)SZ / Gb;
            } else if(SZ >= Mb) {
              u = "Mb";
              v = (double)SZ / Mb;
            } else if(SZ >= Kb) {
              u = "Kb";
              v = (double)SZ / Kb;
            } else {
              u = "b";
              v = SZ;
            }
            snprintf(t, 1024, "malloc(%d) = %.2f%s", size, v, u);
            FinitaInfo(func, file, line, t);
            return malloc(size);
          }
          #undef SZ
          #define SZ size*count
          void* FinitaCallocTrace(size_t count, size_t size, const char* func, const char* file, int line) {
            char t[1024];
            char* u;
            double v;
            if(size >= Gb) {
              u = "Gb";
              v = (double)SZ / Gb;
            } else if(SZ >= Mb) {
              u = "Mb";
              v = (double)SZ / Mb;
            } else if(SZ >= Kb) {
              u = "Kb";
              v = (double)SZ / Kb;
            } else {
              u = "b";
              v = SZ;
            }
            snprintf(t, 1024, "calloc(%d,%d) = %.2f%s", count, size, v, u);
            FinitaInfo(func, file, line, t);
            return calloc(count, size);
          }
        #endif
      $
    end
  end.new

  # @private
  CommonCode = Class.new(AutoC::Code) do
    include CommonMethods
    def entities
      super << AutoC::Type::CommonCode << StringCode << CallStackCode
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

        #ifndef NDEBUG
          extern #{CallStackCode.type} #{CallStackCode.trace};
          #define FINITA_ENTER {#{CallStackCode.element.type} cs = {__FINITA_FUNC__, __FILE__, __LINE__}; #{CallStackCode.push}(&#{CallStackCode.trace}, cs);}
          #define FINITA_LEAVE {#{CallStackCode.pop}(&#{CallStackCode.trace});}
          #define FINITA_RETURN(x) {#{CallStackCode.pop}(&#{CallStackCode.trace}); return x;}
        #else
          #define FINITA_ENTER {}
          #define FINITA_LEAVE {}
          #define FINITA_RETURN(x) {return x;}
        #endif

        #if __STDC_VERSION__ >= 199901L
          #define __FINITA_FUNC__ __func__
        #else
          #define __FINITA_FUNC__ __FUNCTION__
        #endif

        #define FINITA_INFO(msg) FinitaInfo(__FINITA_FUNC__, __FILE__, __LINE__, msg);
        #{extern} void FinitaInfo(const char*, const char*, int, const char*);

        #define FINITA_FAILURE(msg) FinitaFailure(__FINITA_FUNC__, __FILE__, __LINE__, msg);
        #{extern} void FinitaFailure(const char*, const char*, int, const char*);

        #ifndef NDEBUG
          #define FINITA_ASSERT(test) if(!(test)) FinitaAssert(__FINITA_FUNC__, __FILE__, __LINE__, #test);
          #{extern} void FinitaAssert(const char*, const char*, int, const char*);
        #else
          #define FINITA_ASSERT(test)
        #endif

        #{extern} void FinitaAbort(void);

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
        void FinitaInfo(const char* func, const char* file, int line, const char* msg) {
          #{StringCode.type} out;
          #{StringCode.ctor}(&out, NULL);
          #ifdef FINITA_MPI
            #{StringCode.pushFormat}(&out, "\\n[%d] Finita INFO in %s(), %s:%d: %s\\n", FinitaProcessIndex, func, file, line, msg);
            fprintf(stderr, #{StringCode.chars}(&out));
          #else
            #{StringCode.pushFormat}(&out, "\\nFinita INFO in %s(), %s:%d: %s\\n", func, file, line, msg);
            fprintf(stderr, #{StringCode.chars}(&out));
          #endif
        }
        void FinitaFailure(const char* func, const char* file, int line, const char* msg) {
          #{StringCode.type} out;
          #{StringCode.ctor}(&out, NULL);
          #ifdef FINITA_MPI
            #{StringCode.pushFormat}(&out, "\\n[%d] Finita ERROR in %s(), %s:%d: %s\\n", FinitaProcessIndex, func, file, line, msg);
            fprintf(stderr, #{StringCode.chars}(&out));
          #else
            #{StringCode.pushFormat}(&out, "\\nFinita ERROR in %s(), %s:%d: %s\\n", func, file, line, msg);
            fprintf(stderr, #{StringCode.chars}(&out));
          #endif
          #{abort}();
        }
        #ifndef NDEBUG
          void FinitaAssert(const char* func, const char* file, int line, const char* test) {
            #{StringCode.type} out;
            #{StringCode.ctor}(&out, NULL);
            #{StringCode.pushFormat}(&out, "assertion %s failed", test);
            FinitaFailure(func, file, line, #{StringCode.chars}(&out));
          }
        #endif
        #ifndef NDEBUG
          #{CallStackCode.type} #{CallStackCode.trace};
        #endif
        void FinitaAbort(void) {
          #{CallStackCode.dump}();
          #ifdef FINITA_MPI
            MPI_Abort(MPI_COMM_WORLD, 1);
          #else
            abort();
          #endif
        }
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
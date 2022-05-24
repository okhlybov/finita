// gcc -DNDEBUG -g -Ofast -march=native -ffast-math
// icc -DNDEBUG -g -O3 -xhost -fp-model fast -qopt-report=5

#include <stdio.h>
#include <string.h>
#include <malloc.h>
#include <assert.h>

//#define static_N

#ifdef static_N
  #define N 1024
#else
  unsigned N;
#endif
#define T 10000

double *f, *f_;

static inline double* ref(double* __restrict__ f, unsigned x, unsigned y) {
  assert(x < N);
  assert(y < N);
  return &f[N*y+x];
}

#define f(x,y) (*ref(f,x,y))
#define f_(x,y) (*ref(f_,x,y))

void runme() {
  for(unsigned t = 0 ; t < T; ++t) {
    #pragma omp parallel for
    for(int y = 1; y < N-1; ++y) {
      for(int x = 1; x < N-1; ++x) {
        f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
      }
    }
    // sliding layers
  #if 1
    // swapping layers
    {
      double* _ = f;
      f = f_;
      f_ = _;
    }
  #else
    memcpy(f, f_, N*N*sizeof(double));
  #endif
  }
  printf("%e\n", f_(1,1));
}

#if defined(__GNUC__) || defined(__clang__)
  #include <mm_malloc.h>
#endif

int main(int argc, char** argv) {
#ifndef static_N
  N = 1024;
#endif
  f  = _mm_malloc(N*N*sizeof(double), 32);
  f_ = _mm_malloc(N*N*sizeof(double), 32);
  int x = 0; for(int y = 0; y < N; ++y) f_(x,y) = f(x,y) = 1;
   runme();
}
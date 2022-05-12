// -Ofast -march=native -ffast-math

#include <stdio.h>
#include <string.h>
#include <malloc.h>
#include <assert.h>

#define N 1000
#define T 10000

double *f, *f_;

//double* ref(double* restrict f, unsigned x, unsigned y) __attribute_noinline__;

inline double* ref(double* restrict f, unsigned x, unsigned y) {
  assert(x < N);
  assert(y < N);
  return &f[N*y+x];
}

#define f(x,y) (*ref(f,x,y))
#define f_(x,y) (*ref(f_,x,y))

int main(int argc, char** argv) {
  f  = malloc(N*N*sizeof(double));
  f_ = malloc(N*N*sizeof(double));
  int x = 0; for(int y = 0; y < N; ++y) f_(x,y) = f(x,y) = 1;
  for(unsigned t = 0 ; t < T; ++t) {
    for(unsigned y = 1; y < N-1; ++y) {
      for(unsigned x = 1; x < N-1; ++x) {
        f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
      }
    }
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
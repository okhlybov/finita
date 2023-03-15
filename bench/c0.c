#include <stdio.h>

#include "c0_auto.h"

//#define static_N

#ifdef static_N
  #define N 1024
#else
  unsigned N;
#endif

#if 0

void runme() {
  for(unsigned t = 0; t < 10000; ++t) {
#if 1
    #pragma omp parallel for
    C2For(&interior) {
      f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
    }
#else
    #pragma omp parallel
    for(C2Range r = C2RangeNew(&interior); !C2RangeEmpty(&r); C2RangePopFront(&r)) {
      XY n = *C2RangeViewFront(&r);
      const int x = n.x, y = n.y;
      f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
    }
#endif
    C2DRotate(&f);
  }
}

#else

void runme() {
  for(unsigned t = 0; t < 10000; ++t) {
    #pragma omp parallel
    C2For(&interior) {
      f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.05;
    }
    C2DRotate(&f);
  }
}
#endif
#include <complex.h>
int main(int argc, char** argv) {
#ifndef static_N
  N = 1024;
#endif
  c0Setup();
  int x = 0; for(int y = 0; y < N; ++y) f_(x,y) = f(x,y) = 1;
  runme();
  printf("%e\n", creal(f_(1,1)));
  C2DWriteDAT(&f, "%s.dat", "1");
  c0Cleanup();
}

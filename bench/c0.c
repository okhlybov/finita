#include <stdio.h>

#include "c0_auto.h"

#define N 1024

void runme() {
  for(unsigned t = 0; t < 10000; ++t) {
#if 0
    #pragma omp parallel for
    C2For(&interior) {
      f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
    }
#else
    //#pragma omp parallel
    for(C2Range r = C2RangeNew(&interior); !C2RangeEmpty(&r); C2RangePopFront(&r)) {
      XY n = *C2RangeViewFront(&r);
      const int x = n.x, y = n.y;
      f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
    }
#endif
    C2DRotate(&f);
  }
}

int main(int argc, char** argv) {
  c0Setup();
  int x = 0; for(int y = 0; y < N; ++y) f_(x,y) = f(x,y) = 1;
  runme();
  printf("%e\n", f_(1,1));
}
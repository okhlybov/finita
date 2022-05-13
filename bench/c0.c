#include <stdio.h>

#include "c0_auto.h"

#define sn

#ifdef sn
  #define N 1000
#else
  size_t N;
#endif

void runme() {
  for(unsigned t = 0; t < 1000; ++t) {
    #if 1
      for(unsigned y = 1; y < N-1; ++y) {
        for(unsigned x = 1; x < N-1; ++x) {
          f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
        }
      }
    #else
      for(InteriorRange r = InteriorRangeNew(&interior); !InteriorRangeEmpty(&r); InteriorRangePopFront(&r)) {
        const XY n = InteriorRangeTakeFront(&r);
        const int x = n.x, y = n.y;
        f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
      }
    #endif
    FieldRotate(&f);
  }
}

int main(int argc, char** argv) {
#ifndef sn
  N = 1000;
#endif
  c0Setup();
  int x = 0; for(int y = 0; y < N; ++y) f_(x,y) = f(x,y) = 1;
  runme();
  printf("%e\n", f_(1,1));
}
#include <stdio.h>
#include "test_auto.h"


int main(int argc, char** argv) {
  testSetup();
  #define F(x,y) *C2FView0(&F, (XY){x,y})
  #define F_(t,x,y) *C2FView(&F, (XY){x,y}, t)
  F(1,1) = 3;
  F_(1,1,1) = -3;
  #pragma omp parallel
  for(C2Range r = C2RangeNew(&g1); !C2RangeEmpty(&r); C2RangePopFront(&r)) {
    const XY n = C2RangeTakeFront(&r);
    printf("(%d,%d)=%e\n", n.x, n.y, F(n.x,n.y) * F_(1, n.x,n.y));
  }
  testCleanup();
}

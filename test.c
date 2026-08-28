#include <stdio.h>
#include "test_auto.h"


int main(int argc, char** argv) {
  N2 a = (N2){1,1};
  N2 b = (N2){10,20};
  C2* g = C2New(a,b);
  printf("size=%d\n", C2Size(g));
  C2Index(g, b);
  C2Index(g, C2Node(g, 20));
  C2Field* f = C2FieldNew(g, 5);
  *C2FieldAccess(f, (N2){3,3}, 0) = -3i;
  C2FieldRotate(f, -5);
  C2FieldRotate(f, 3);
  C2Free(g);
  C2FieldFree(f);
  T(((N2){1,1})) = 8;
  T_(b,1) *= 2;
  
  #pragma omp parallel
  C2_XY(T->mesh) {
    T(((N2){x+1,y})) = 1;
  }
  
  return 0;
}

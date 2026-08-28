#include <stdio.h>
#include "test_auto.h"


int main(int argc, char** argv) {
  N2 a = (N2){1,1};
  N2 b = (N2){10,20};
  const C2* g = C2New(a,b);
  printf("size=%d\n", C2Size(g));
  C2Index(g, b);
  C2Index(g, C2Node(g, 20));
  C2Field* f = C2FieldNew(g);
  f->elements[0] = 6;
  C2Free(g);
  return 0;
}

#include "_test_auto.h"

#include <stdio.h>

#define N 3
#define NF 5

int main(int argc, char **argv) {
  N3Set s;
  N3SetCreate(&s);
  for(int f = 1; f <= NF; ++f)
  for(int x = 1; x <= N; ++x) for(int y = 1; y <= N; ++y) for(int z = 1; z <= N; ++z) {
    N3SetPush(&s, N3(x,y,z,f));
  }
  //N3SetPush(&s, N3(1,-1,1,1));
  printf("%zu\n", N3SetSize(&s));
  N3Vector v;
  ptrdiff_t i = 0;
  N3VectorCreateSize(&v, N3SetSize(&s));
  for(N3SetRange r = N3SetRangeNew(&s); !N3SetRangeEmpty(&r); N3SetRangePopFront(&r)) {
    N3VectorSet(&v, i++, N3SetRangeTakeFront(&r));
  }
  N3VectorSort(&v, 1);
  for(N3VectorRange r = N3VectorRangeNew(&v); !N3VectorRangeEmpty(&r); N3VectorRangePopFront(&r)) {
    N3 n = N3VectorRangeTakeFront(&r);
    printf("%d %d %d - %d\n", N3X(n), N3Y(n), N3Z(n), N3Field(n));
  }
  W w;
  WCreate(&w);
  printf("%d/%d\n", WThread(&w), WThreads(&w));
  WDestroy(&w);
  N3SetDestroy(&s);
  return 0;
}

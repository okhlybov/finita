#include "_finita_auto.h"

#include <stdio.h>

int main(int argc, char **argv) {
  CXY g;
  CXYCreateWH(&g, 5, 10);
  CXY_FOREACH(&g) {
    printf("%d,%d\n", x, y);
  }
  size_t i = CXYIndex(&g, (XY){3,8});
  printf("%zu\n", i);
  XY node = CXYNode(&g, i);
  printf("%d %d\n", node.x, node.y);
  CXYDestroy(&g);
  return 0;
}

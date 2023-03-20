#include "_finita_auto.h"

#include <stdio.h>

int main(int argc, char **argv) {
  CXY g;
  CXYCreate(&g);
  CXY_FOREACH(g);
  CXYDestroy(&g);
  return 0;
}

#include "_test_auto.h"

#include <stdio.h>

int main(int argc, char **argv) {
  CString msg;
  CStringCreateFormat(&msg, "Hello %s!\n", "test");
  printf(msg);
  CStringDestroy(&msg);
  return 0;
}

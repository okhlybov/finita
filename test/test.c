#include "_test_auto.h"

#include <stdio.h>

int main(int argc, char **argv) {
  N3 n = N3(0,0,0,0);
  N3Set s;
  N3SetCreate(&s);
  N3SetPush(&s, n);
  N3SetPut(&s, N3(1,1,1,1));
  return 0;
}

// -Ofast -march=native -ffast-math

#include <stdio.h>
#include <string.h>

#define N 1000
#define T 10000

double f[N][N], f_[N][N];

#define f(x,y) f[x][y]
#define f_(x,y) f_[x][y]

int main(int argc, char** argv) {
  int x = 0; for(int y = 0; y < N; ++y) f_(x,y) = f_(x,y) = 1;
  for(unsigned t = 0 ; t < T; ++t) {
    for(unsigned y = 1; y < N-1; ++y) {
      for(unsigned x = 1; x < N-1; ++x) {
        f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1;
      }
    }
    // sliding layers
  #if 0
    for(unsigned y = 0; y < N; ++y) {
      for(unsigned x = 0; x < N; ++x) {
        f(x,y) = f_(x,y);
      }
    }
  #else
    memcpy(f, f_, sizeof(f));
  #endif
  }
  printf("%e\n", f_(1,1));
}
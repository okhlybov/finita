#include <stdio.h>
#include "Problem_auto.h"

void FinitaAbort() {
   abort();
}
int main(int argc, char** argv) {
    int i, x, y;
	FILE* f;
    A = B = 50;
    ProblemSetup(argc, argv);
    for(i = 0; i < 10; ++i) ProblemSystemSolve();
    ProblemCleanup();
    printf("%e\n", F(0,0,0));
    printf("%e\n", F(1,1,0));
    f = fopen("F.dat", "wt");
    for(x = 0; x < A; ++x)
    for(y = 0; y < B; ++y)
    {
        fprintf(f, "%d\t%d\t%e\n", x, y, F(x,y,0));
    }
    fclose(f);
    return 0;
}

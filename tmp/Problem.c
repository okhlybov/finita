#include <stdio.h>
#include "Problem_auto.h"

void FinitaAbort() {
   abort();
}

int main(int argc, char** argv) {
    int x, y;
    A = B = 5;
    ProblemSetup(argc, argv);
    ProblemSystemSolve();
    ProblemCleanup();
    printf("%e\n", F(0,0,0));
    printf("%e\n", F(1,1,0));
    /*printf("%e\n", G(1,1,0));*/
    FILE* f = fopen("F.dat", "wt");
    for(x = 0; x < A; ++x)
    for(y = 0; y < B; ++y)
    {
        fprintf(f, "%d\t%d\t%e\n", x, y, F(x,y,0));
    }
    fclose(f);
    return 0;
}

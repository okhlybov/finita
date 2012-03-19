#include <stdio.h>
#include "Problem_auto.h"

void FinitaAbort() {
   abort();
}

int main(int argc, char** argv) {
    A = B = 3;
    ProblemSetup(argc, argv);
    ProblemSystemSolve();
    ProblemCleanup();
    printf("%e\n", F(0,0,0));
    printf("%e\n", F(1,1,0));
    /*printf("%e\n", G(1,1,0));*/
    return 0;
}

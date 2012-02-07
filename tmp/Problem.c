#include "Problem.auto.h"

void FinitaAbort() {
   abort();
}

int main(int argc, char** argv) {
    A = B = 10;
    ProblemSetup(argc, argv);
    F(9,0,0);
    return 0;
}

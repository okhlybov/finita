#include "Cavity.auto.h"

int main(int argc, char** argv) {
    NX = NY = 11;
    A = NX;
    B = NY;
    CavitySetup(argc, argv);
    CavitySystemSolve();
    CavityCleanup();
    return 0;
}
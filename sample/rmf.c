#include <stdio.h>

#include "RMF.auto.h"

#define PRINT_FIELD(file_name, f) \
FINITA_HEAD { \
	int x, y; \
	FILE* file = fopen(file_name, "wt"); \
	for(x = 0; x < NX; ++x) \
	for(y = 0; y < NY; ++y) \
		{ \
			fprintf(file, "%e\t%e\t%e\n", R(x, y, 0), Z(x, y, 0), f(x, y, 0)); \
		} \
	fclose(file); \
}

int main(int argc, char** argv) {
    int x, y;
    NX = 51;
    NY = 101;
    A = (NX-1)/1.0;
    B = (NY-1)/2.0;
    double _[] = {10, 1e2, 1e3, 1e4, 1e5, -1}, *p = _;
    RMFSetup(argc, argv);
    for(x = 0; x < NX; ++x) for(y = 0; y < NY; ++y) {
        R(x, y, 0) = x/A;
        Z(x, y, 0) = y/B;
    }
    //RMFFormSolve();
    /*while((Tm = *p++) >= 0) {
        FINITA_HEAD printf("*** Tm = %e\n", Tm);
    }*/
    PRINT_FIELD("P.dat", P);
    PRINT_FIELD("F.dat", F);
    RMFCleanup();
    return 0;
}

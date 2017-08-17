#include "tmf_auto.h"

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
    NX = 25;
    NY = 50;
    A = (NX-1)/1.0;
    B = (NY-1)/2.0;
    double _[] = {10, 1e2, 1e3, 1e4, 1e5, -1}, *p = _;
    TMFSetup(argc, argv);
    /*
        Setting up the coordinate transformation.
        This has to be done after the problem setup phase as the fields need to be constructed
        but before the solution phase because these fields are a part of equations.
    */
    for(x = 0; x < NX; ++x) for(y = 0; y < NY; ++y) {
        R(x, y, 0) = x/A;
        Z(x, y, 0) = y/B;
    }
    /* Employing the continuation technique with respect to Tm to attain the solution for the flow */
    while((Tm = *p++) >= 0) {
        FINITA_HEAD printf("*** Tm = %e\n", Tm);
        /* Attain the solution for the flow field */
        TMFFlowSolve();
    }
    PRINT_FIELD("Psi.dat", Psi);
    PRINT_FIELD("Phi.dat", Phi);
    PRINT_FIELD("T.dat", T);
    TMFCleanup();
    return 0;
}

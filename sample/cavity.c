#include <stdio.h>

#include "cavity_auto.h"

#define WRITE_FIELD(file_name, f) \
FINITA_HEAD { \
	int x, y; \
	FILE* file = fopen(file_name, "wt"); \
	for(x = 0; x < NX; ++x) \
	for(y = 0; y < NY; ++y) \
		{ \
			fprintf(file, "%d\t%d\t%e\n", x, y, f(x, y, 0)); \
		} \
	fclose(file); \
}

int main(int argc, char** argv) {
    NX = NY = 51;
    A = (NX-1)/1.0;
    B = (NY-1)/1.0;
    Pr = 1;
    double _[] = {1, 1e4, 1e5, 5e5, -1}, *p = _;
    CavitySetup(argc, argv);
    while((Gr = *p++) >= 0) CavitySystemSolve();
    WRITE_FIELD("T.dat", T);
    WRITE_FIELD("Psi.dat", Psi);
    WRITE_FIELD("Phi.dat", Phi);
    CavityCleanup();
    return 0;
}

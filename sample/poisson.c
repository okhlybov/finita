#include "poisson_auto.h"

#define WRITE_FIELD(file_name, f) \
FINITA_HEAD { \
	int x, y; \
	FILE* file = fopen(file_name, "wt"); \
	for(x = 1; x <= NX; ++x) \
	for(y = 1; y <= NY; ++y) \
		{ \
			fprintf(file, "%d\t%d\t%e\n", x, y, f(x, y, 0)); \
		} \
	fclose(file); \
}

int main(int argc, char** argv) {
    NX = NY = 100;
    Rho = -1;
    PoissonSetup(argc, argv);
    PoissonSystemSolve();
    WRITE_FIELD("F.dat", F);
    PoissonCleanup();
    return 0;
}
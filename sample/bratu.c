/* Import the auto-generated interface part */
#include "bratu_auto.h"

/* Define the field writer macro */
#define WRITE_FIELD(file_name, f) \
FINITA_HEAD { \
	int x, y, z; \
	FILE* file = fopen(file_name, "wt"); \
	for(x = 1; x <= NX; ++x) \
	for(y = 1; y <= NY; ++y) \
	for(z = 1; z <= NZ; ++z) \
		{ \
			fprintf(file, "%d\t%d\t%d\t%e\n", x, y, z, f(x, y, z)); \
		} \
	fclose(file); \
}

/* The code entry point is under user's control  */
int main(int argc, char** argv) {
    /* Set up the problem dimensions; this has to be done prior initializing the auto-generated part */
    NX = NY = NZ = 10;
    /* Set up the parameter */
    Lambda = 1e-3;
    /* Initialize the auto-generated part */
    BratuSetup(argc, argv);
    /* Solve the system */
    BratuSystemSolve();
    /* Dump the computed field F */
    WRITE_FIELD("F.dat", F);
    /* Finalize the auto-generated part*/
    BratuCleanup();
    return 0;
}
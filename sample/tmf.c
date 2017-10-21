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

#include <gsl/gsl_sf_bessel.h>

double IxaR(int x, int y, int z) {
	double aR = -1/*a*/ *R(x,y,z);
	return gsl_sf_bessel_I1(aR)*(gsl_sf_bessel_I0(aR) + gsl_sf_bessel_In(2, aR));
}

double Tm;

int main(int argc, char** argv) {
    int x, y;
	#define S 2
    NX = S*25;
    NY = S*50;
    Pr = 1;
    Gr = 10;
    A = (NX-1)/1.0;
    B = (NY-1)/2.0;
    double _[] = {10, 1e3, 1e4, 1e5, 2e5, 5e5, 1e6, 2e6, 2.5e6, -1}, *p = _;
    TMFSetup(argc, argv);
    /*
        Setting up the coordinate transformation.
        This has to be done after the problem setup phase as the fields need to be constructed
        but before the solution phase because these fields are a part of equations.
    */
    for(x = 0; x < NX; ++x) for(y = 0; y < NY; ++y) {
        R(x,y,0) = x/A;
        Z(x,y,0) = y/B;
        T(x,y,0) = Z(x,y,0); /* Have to initialize T field to avoid misbehaving of the Newton method for nonlinear system */
    }
    /* Employing the continuation technique with respect to Tm to attain the solution for the flow */
    while((Tm = *p++) >= 0) {
        FINITA_HEAD {
            printf("*** Tm = %e\n", Tm);
            fflush(stdout);
        }
        /* Attain the solution for the flow field */
        TMFFlowSolve();
    }
    PRINT_FIELD("Psi.dat", Psi);
    PRINT_FIELD("Phi.dat", Phi);
    PRINT_FIELD("T.dat", T);
    PRINT_FIELD("Vr.dat", Vr);
    PRINT_FIELD("Vz.dat", Vz);
    PRINT_FIELD("R.dat", R);
    PRINT_FIELD("Z.dat", Z);
    TMFCleanup();
    return 0;
}

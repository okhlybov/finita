#include <math.h>

#include "tmfd_auto.h"

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
    double aR = a*R(x,y,z);
    return (1.0/RhoM)*pow(B,2)*Sigma*Omega*gsl_sf_bessel_I1(aR)*(gsl_sf_bessel_I0(aR) + gsl_sf_bessel_In(2, aR));
}

int main(int argc, char** argv) {
    int x, y;
	#define S 2
    NX = S*25;
    NY = S*50;
    Rc = 1.27; // [cm]
    Hc = Rc*2; // [cm]
    Nu = 1.3e-3; // [cm^2/s]
    RhoM = 5.5; // [g/cm^3]
    Sigma = 2.37e6/*[Sm/m]*/ * 1e-11; // --> [CGS/cm]
    Omega = 300/*[Hz]*/ *(2*M_PI); // --> [Rad/s]
    a = -1/Rc;
    DX = (NX-1)/Rc;
    DY = (NY-1)/Hc;
    double _[] = {1e-5, 1e-4, 5e-4, 6e-4, 8e-4, 1e-3, 1.5e-3, 1.8e-3, 1.9e-3, 2e-3, -1}, *p = _; // [T]
    TMFdSetup(argc, argv);
    /*
        Setting up the coordinate transformation.
        This has to be done after the problem setup phase as the fields need to be constructed
        but before the solution phase because these fields are a part of equations.
    */
    for(x = 0; x < NX; ++x) for(y = 0; y < NY; ++y) {
        R(x,y,0) = x/DX;
        Z(x,y,0) = y/DY;
    }
    /* Employing the continuation technique with respect to Tm to attain the solution for the flow */
    while((B = *p++) >= 0) {
        B = B/*[T]*/ *1e4; // --> [Gs]
        FINITA_HEAD {
            printf("*** B = %e [Gs], Tm = %e\n", B,pow(B,2)*Omega*Sigma*pow(Rc,4)/(2*RhoM*pow(Nu,2)));
            fflush(stdout);
        }
        /* Attain the solution for the flow field */
        TMFdFlowSolve();
    }
    PRINT_FIELD("Psi.dat", Psi);
    PRINT_FIELD("Phi.dat", Phi);
    PRINT_FIELD("Vr.dat", Vr);
    PRINT_FIELD("Vz.dat", Vz);
    PRINT_FIELD("R.dat", R);
    PRINT_FIELD("Z.dat", Z);
    TMFdCleanup();
    return 0;
}

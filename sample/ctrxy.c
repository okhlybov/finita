#include <math.h>
#include <stdio.h>
#include "ctrxy_auto.h"

#define M_PI 3.1415926

#define WRITE_FIELD(file_name, domain, f) \
    FINITA_HEAD { \
	FILE* file = fopen(file_name, "wt"); \
        FINITA_FORXYZ_BEGIN(domain) \
            fprintf(file, "%e\t%e\t%e\n", domain##X(x,y,z), domain##Y(x,y,z), f(x,y,z)); \
        FINITA_FORXYZ_END \
	fclose(file); \
    }

int main(int argc, char** argv) {
    double H, W;
    H = 1;
    W = 1;
    X1 = Y1 = 1;
    X2 = Y2 = 100;
    CtrXYSetup(argc, argv);
    FINITA_FORXYZ_BEGIN(Top)
        TopX(x,y,z) = W*(x-X1)/(X2-X1);
        TopY(x,y,z) = ( H-0.5*sin(M_PI*(x-X1)/(X2-X1)) )*(y-Y1)/(Y2-Y1); /* Concave top domain border */
    FINITA_FORXYZ_END
    CtrXYTopSolve();
    CtrXYSystemSolve();
    WRITE_FIELD("F.dat", Top, F);
    CtrXYCleanup();
    return 0;
}
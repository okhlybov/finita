#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "problem.auto.h"


//#define D3


#ifdef D3
#define PRINT_FIELD(out, f) \
{ \
	int x, y, z; \
	for(x = 0; x < N; ++x) \
	for(y = 0; y < N; ++y) \
	for(z = 0; z < N; ++z) \
		{ \
			fprintf(out, "%d\t%d\t%d\t%e\n", x, y, z, f(x,y,z)); \
		} \
}
#else
#define PRINT_FIELD(out, f) \
{ \
	int x, y; \
	for(x = 0; x < N; ++x) \
	for(y = 0; y < N; ++y) \
		{ \
			fprintf(out, "%d\t%d\t%e\n", x, y, f(x,y,0)); \
		} \
}
#endif


int main(int argc, char** argv)
{
    clock_t c;
	N = 51;
	ProblemSetup(argc, argv);
{
	int x, y;
	for(x = 0; x < N; ++x)
	for(y = 0; y < N; ++y)
		{
			F(x,y,0) = 0;
			G(x,y,0) = 1e-4;
		}
#ifdef D3
	for(x = 0; x < N; ++x) for(y = 0; y < N; ++y) F(x,y,0) = 1;
#else
	for(x = 0; x < N; ++x) F(x,0,0) = 1;
#endif
}
    ProblemSystemSolve();
    #if 1
    FINITA_HEAD {
        //printf("F:\n");
        //PRINT_FIELD(stdout, F);
        //printf("G:\n");
        //PRINT_FIELD(stdout, G);
        FILE* f = fopen("F.dat", "wt");
        PRINT_FIELD(f, F);
        fclose(f);
	}
	#endif
	ProblemCleanup();
	return 0;
}

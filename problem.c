#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "problem.auto.h"


#define PRINT_FIELD(out, f) \
{ \
	int x, y; \
	for(x = 0; x < N; ++x) \
	{ \
		for(y = 0; y < N; ++y) \
		{ \
			fprintf(out, "%d\t%d\t%e\n", x, y, f(x,y,0)); \
		} \
	} \
}

int main(int argc, char** argv)
{
    clock_t c;
	N = 150;
	ProblemSetup(argc, argv);
{
	int x, y;
	for(x = 0; x < N; ++x)
	{
		for(y = 0; y < N; ++y)
		{
			F(x,y,0) = 0;
			G(x,y,0) = 1e-5;
		}
	}
	for(x = 0; x < N; ++x) F(x,0,0) = 1;
}
    ProblemSystemSolve();
	printf("F:\n");
	//FINITA_HEAD PRINT_FIELD(stdout, F);
	printf("G:\n");
	//FINITA_HEAD PRINT_FIELD(stdout, G);
	{
	    FILE* f = fopen("F.dat", "wt");
	    PRINT_FIELD(f, F);
	    fclose(f);
	}
	ProblemCleanup();
	return 0;
}

#include <stdio.h>
#include <stdlib.h>
#include "problem.auto.h"

void PrintF(FILE* out)
{
	int x, y;
	for(x = 0; x < N; ++x)
	{
		for(y = 0; y < N; ++y)
		{
			fprintf(out, "%d\t%d\t%e\n", x, y, F(x,y,0));
		}
	}
}

int main(int argc, char** argv)
{
	N = 3;
	ProblemSetup(argc, argv);
#ifdef FINITA_MPI
	printf("[%d]--\n", FinitaProcessIndex);
{
	int x, y;
	for(x = 0; x < N; ++x)
	{
		for(y = 0; y < N; ++y)
		{
			F(x,y,0) = FinitaProcessIndex;
		}
	}
}
#endif
	PrintF(stdout);
	ProblemSystemSolve();
	printf("--\n");
	PrintF(stdout);
	ProblemCleanup();
	return 0;
}

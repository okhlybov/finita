#include <stdio.h>
#include <stdlib.h>
#include <time.h>
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
    clock_t c;
	N = 5;
	ProblemSetup(argc, argv);
{
	int x, y;
	for(x = 0; x < N; ++x)
	{
		for(y = 0; y < N; ++y)
		{
			F(x,y,0) = 1;
		}
	}
}
	ProblemSystemSolve();
	FINITA_HEAD PrintF(stdout);
	ProblemCleanup();
	return 0;
}

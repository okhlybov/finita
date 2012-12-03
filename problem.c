#include <stdlib.h>
#include <stdio.h>
#include "problem.auto.h"

int main(int argc, char** argv) {
	N = 10;
	ProblemSetup(argc, argv);
	printf("%e\n", F(1,1,1));
	ProblemSystemSolve();
	printf("%e\n", F(1,1,1));
	ProblemCleanup();
}
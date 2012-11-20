#include <stdio.h>
#include "field_code_test.auto.h"

static int double_print(double v, int x, int y, int z) {
    printf("[%d,%d,%d]=%e\n", x, y, z, v);
    return 1;
}

int main(int argc, char** argv) {
    FinitaFloatRectField dr;
    FinitaFloatRectFieldCtor(&dr, 1, 2, 1, 2, 1, 2);
    printf("size=%d\n", FinitaFloatRectFieldSize(&dr));
    printf("within=%d\n", FinitaFloatRectFieldWithin(&dr, 0, 0, 0));
    *FinitaFloatRectFieldRef(&dr, 1, 1, 2) = -1;
    *FinitaFloatRectFieldRef(&dr, 1, 2, 1) = +1;
    FinitaFloatRectFieldForeach(&dr, double_print);
    return 0;
}
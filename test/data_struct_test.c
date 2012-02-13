#include <stdio.h>
#include <string.h>

#include "data_struct_test.auto.h"

static void IntSlistTest() {
    IntSlist is;
    IntSlistCtor(&is);
    IntSlistAppend(&is, 2);
    IntSlistPrepend(&is, 1);
    IntSlistAppend(&is, 3);
    IntSlistAppend(&is, 4);
    IntSlistPrepend(&is, 0);
    IntSlistReplace(&is, 3, 33);
    IntSlistReplace(&is, 4, 44);
    IntSlistReplace(&is, 5, 55);
    printf("size=%d\n", IntSlistSize(&is));
    printf("first=%d last=%d\n", IntSlistFirst(&is), IntSlistLast(&is));
    {
        IntSlistIt it;
        IntSlistItCtor(&it, &is);
        while(IntSlistItHasNext(&it)) {
            printf("%d ", IntSlistItNext(&it));
        }
        puts("\n");
    }
}

int IntHasher(int x) {
    return x;
}

int IntComparator(int x, int y) {
    return x == y;
}

static void IntHsetTest() {
    IntHset is;
    IntHsetCtor(&is, 10);
	IntHsetPut(&is, 2);
	IntHsetPut(&is, 1);
	IntHsetPut(&is, 0);
	IntHsetPut(&is, 4);
	IntHsetPut(&is, 3);
	IntHsetPut(&is, 0);
	IntHsetPut(&is, 0);
    printf("size=%d\n", IntHsetSize(&is));
    printf("contains=%d\n", IntHsetContains(&is, 4));
	{
		IntHsetIt it;
		IntHsetItCtor(&it, &is);
		while(IntHsetItHasNext(&it)) {
            printf("%d ", IntHsetItNext(&it));
		}
        puts("\n");
	}
}

int PcharHasher(char* x) {
	int i = 0;
	char* p = x;
	while(*p++) i += *p;
	return i;
}

int PcharComparator(char* x, char* y) {
	return strcmp(x, y) == 0;
}

static void StrHsetTest() {
	StrHset ss;
	StrHsetCtor(&ss, 10);
	StrHsetPut(&ss, "ABC");
	StrHsetPut(&ss, "A");
	StrHsetPut(&ss, "B");
	StrHsetPut(&ss, "C");
	StrHsetPut(&ss, "A");
	StrHsetPut(&ss, "ABCCBA");
    printf("size=%d\n", StrHsetSize(&ss));
    printf("contains=%d\n", StrHsetContains(&ss, "Zzz"));
	{
		StrHsetIt it;
		StrHsetItCtor(&it, &ss);
		while(StrHsetItHasNext(&it)) {
            printf("%s ", StrHsetItNext(&it));
		}
        puts("\n");
	}
}

int StrIntHmapKeyHasher(char* x) {
	int i = 0;
	char* p = x;
	while(*p++) i += *p;
	return i;
}

int StrIntHmapKeyComparator(char* x, char* y) {
	return strcmp(x, y) == 0;
}

static void StrIntHmapTest() {
    StrIntHmap self;
    char* s;
    StrIntHmapCtor(&self, 10);
    StrIntHmapPut(&self, "A", 1);
    StrIntHmapPut(&self, "B", 2);
    StrIntHmapPut(&self, "A", 2);
    StrIntHmapPut(&self, "Zzz", 999);
    StrIntHmapPut(&self, "B", 3);
    StrIntHmapPut(&self, "C", 4);
    printf("size=%d\n", StrIntHmapSize(&self));
    printf("contains=%d\n", StrIntHmapContainsKey(&self, "AA"));
    printf("contains=%d\n", StrIntHmapContainsKey(&self, "Zzz"));
    s = "A"; printf("%s => %d\n", s, StrIntHmapGet(&self, s));
    s = "B"; printf("%s => %d\n", s, StrIntHmapGet(&self, s));
    s = "C"; printf("%s => %d\n", s, StrIntHmapGet(&self, s));
    {
        StrIntHmapIt it;
        StrIntHmapItCtor(&it, &self);
        printf("[");
        while(StrIntHmapItHasNext(&it)) {
            char* key = StrIntHmapItNextKey(&it);
            printf("%s => %d,", key, StrIntHmapGet(&self, key));
        }
        printf("]\n");
    }
}

int main(int argc, char** argv) {
    IntSlistTest();
    IntHsetTest();
    StrHsetTest();
    StrIntHmapTest();
    return 0;
}

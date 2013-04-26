### Begin custom definitions

program = problem

sources = problem.c problem.auto1.c

packages = PETSC_DMG

CPPFLAGS = -g -ansi -pedantic -std=c99 -pg #-O3 -DNDEBUG
LDFLAGS = -g -pg

### End custom definitions

ifeq ($(OS),Windows_NT)
PROGEXT ?= .exe
LIBEXT ?= .lib
OBJEXT ?= .obj
else
PROGEXT ?=
LIBEXT ?= .a
OBJEXT ?= .o
endif

OBJS := $(addsuffix $(OBJEXT),$(basename $(sources)))

cppflags := $(foreach package,$(packages),$(cppflags) $($(package)_CPPFLAGS))

ldflags := $(foreach package,$(packages),$(ldflags) $($(package)_LDFLAGS))

ldlibs := $(foreach package,$(packages),$(ldlibs) $($(package)_LDLIBS))

CPPFLAGS := $(cppflags) $(CPPFLAGS)

LDFLAGS := $(ldflags) $(LDFLAGS)

LDLIBS := $(ldlibs) $(LDLIBS)

PROG := $(program)$(PROGEXT)

all : $(PROG)

run : $(PROG)
	$(PROG)

$(PROG) : $(OBJS)
	$(LINK.o) $^ $(LOADLIBES) $(LDLIBS) -o $@

%$(OBJEXT) : %.c
	$(COMPILE.c) $(OUTPUT_OPTION) $<

%$(OBJEXT) : %.f
	$(COMPILE.f) $(OUTPUT_OPTION) $<

%$(OBJEXT) : %.F
	$(COMPILE.F) $(OUTPUT_OPTION) $<

clean :
	$(RM) $(PROG) $(OBJS)

problem.auto1.obj problem.obj : problem.auto.h
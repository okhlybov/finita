# This is a template of the WHPC-friendly makefile for building single executable
# from multiple source files written in C, C++ and/or FORTRAN languages.
# The makefile requires GCC compilers and GNU Make.
# It should be usable on UNIX systems with little or no modifications.
# The makefile does its best to handle source dependencies for all languages
# including FORTRAN.


### [MANDATORY] user-defined variables which must be set.

# Name of executable without extension, ex. <runme>.
# On Windows the executable <runme.exe> will be produced.
PROG ?= tmfd

PRJ = $(PROG)

SRC_RB = sample/$(PRJ).rb
SRC_C = $(PRJ)_auto.c
SRC_H = $(PRJ)_auto.h

# Space-separated list of source files which constitute the program.
# C, C++ and FORTRAN source files may be specified simultaneously.
# Ex. <main.c lib.cpp solver.f intf.f90>.
# The following file extensions are recognized:
# <.c> for C language,
# <.cpp .cxx .cc> for C++ language,
# <.f .F .for .f90> for FORTRAN language.
SRC ?= sample/$(PRJ).c $(SRC_C)

### [optional] user-definable variables which are normally set.

# Space-separated list of WHPC packages to be used, ex. <mpi blas lapack>.
# This list will be passed to the PkgConfig utility to determine proper
# compile and link command line options.
PKG ?= lis_dso gsl

# Options passed to the C preprocessor, ex. <-DNDEBUG>.
# The same options will used to preprocess all kinds of sources
# (FORTRAN included).
CPPFLAGS ?= -I. #-DNDEBUG

# Language-neutral options passed to all compilers, ex. <-O3>.
# This variable is mainly intended to control the compilers optimizations.
OPTFLAGS ?= -O3 #-ansi -Wall -pedantic -g #-x c++


### [extra] user-definable variables that might be of use.

# Below are the language-specific compiler flags.
# Normally these need not contain common optimization flags which
# go into the OPTFLAGS variable.

# Options passed to the C compiler.
CFLAGS ?=

# Options passed to the C++ compiler.
CXXFLAGS ?=

# Options passed to the FORTRAN compiler.
FFLAGS ?=

# Options passed to the linker, ex. <-s>.
LDFLAGS ?= -g

# Extra library options, ex. <-lm>.
LDLIBS ?=

### No user-serviceable parts below ###

ifeq ($(OS),Windows_NT)
EXEXT := .exe
# Rough Windows equivalent of the UNIX's <rm -f>
RM := erase /f /s
endif

CPAT := %.c
CEXT := $(suffix $(CPAT))
CSRC := $(filter $(CPAT),$(SRC))

CXXPAT := %.cc %.cpp %.cxx
CXXEXT := $(suffix $(CXXPAT))
CXXSRC := $(filter $(CXXPAT),$(SRC))

FORPAT := %.f %.F %.for %.f90
FOREXT := $(suffix $(FORPAT))
FORSRC := $(filter $(FORPAT),$(SRC))

OBJPAT := %.o
OBJEXT := $(suffix $(OBJPAT))
OBJ := $(addsuffix $(OBJEXT),$(basename $(SRC)))

EXE := $(PROG)$(EXEXT)

DEPEXT := .d
DEP := $(addsuffix $(DEPEXT),$(basename $(SRC)))

MODEXT := .mod
MOD := $(addsuffix $(MODEXT),$(basename $(FORSRC)))

PKG_CONFIG ?= pkg-config

ifneq ($(PKG),)
PKGCFLAGS := $(shell $(PKG_CONFIG) $(PKG) --cflags)
PKGLIBS := $(shell $(PKG_CONFIG) $(PKG) --libs --static)
endif

CFLAGS += $(OPTFLAGS) $(PKGCFLAGS)
CXXFLAGS += $(OPTFLAGS) $(PKGCFLAGS)
FFLAGS += $(OPTFLAGS) $(PKGCFLAGS)
LDLIBS += $(PKGLIBS)

# Determine extra required runtimes based upon the sources used
STDLIBS = -lgcc -lstdc++
ifneq ($(filter $(FOREXT),$(suffix $(SRC))),)
STDLIBS += -lgfortran
endif
ifneq ($(filter $(CXXEXT),$(suffix $(SRC))),)
STDLIBS += -lstdc++
endif

.SUFFIXES:
.SUFFIXES: $(EXEXT) $(OBJEXT) $(CEXT) $(CXXEXT) $(FOREXT)

# Add GCC-specific dependency info generation options
DEPFLAGS = -MMD -MP -MT $(addsuffix $(OBJEXT),$(basename $@)) -MT $(addsuffix $(DEPEXT),$(basename $@))
COMPILE.c += $(DEPFLAGS)
COMPILE.cc += $(DEPFLAGS)
COMPILE.F += -cpp $(DEPFLAGS) -MT $(addsuffix $(MODEXT),$(basename $@))

# Pass all FORTRAN sources through the CPP to force generate the dependency info
COMPILE.f = $(COMPILE.F)

all : $(EXE)

$(EXE) : $(OBJ)
	$(LINK.o) -o $@ $^ $(LDLIBS) $(STDLIBS)

# Extra implicit rules for the FORTRAN language absent in the GNU Make rules catalogue

$(OBJPAT) : %.for
	$(COMPILE.f) -o $@ $<

$(OBJPAT) : %.f90
	$(COMPILE.f) -o $@ $<

clean :
	$(RM) $(EXE) $(OBJ) $(MOD) $(DEP)

run : $(PROG)
	./$(PROG) -info

$(SRC_H) : $(SRC_RB)
	ruby -I./lib bin/finitac $<

-include $(DEP)

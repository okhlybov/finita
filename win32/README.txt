Finita :: http://finita.sourceforge.net/
========================================

What's in this distribution?
-----------------------------

This is the self-contained Windows distribution of Finita, a package for solving complex PDE/algebraic systems of equations numerically using grid methods.

What is Finita?
---------------

Finita is package for solving complex PDE/algebraic systems of equations numerically using grid methods.

It is essentially a C source code generator in that instead of solving the problems directly it generates a C program which is to perform the actual computations.

The auto-generated C source code is highly portable and can be compiled with an ANSI C compiler on a wide array of systems ranging from Windows workstations to non-x86 high peformance *NIX clusters with no source code modifications.

Finita generates either sequental or parallel codes at user's discretion and makes use of a few widespread high performance (non)linear solvers such as SuperLU, MUMPS, PETSc etc.

How to use it?
--------------

At user level Finita provides the command-line driver finitac which processes the user-supplied problem description and generates the C source code. The Windows installer can augment system-wide path with the directory containing the finitac executable which can be then called from within command-line shell, makefiles etc.

The finitac invokation is as follows:
	
	> finitac problem.rb

where problem.rb is the problem description file.

On successful execution the finitac yields a set of C source files and a C header file which are when accompatied by the hand-crafted C driver constitute a program for solving the respective problem.

Anything else for Windows users?
--------------------------------

Since Finita is a source code generator, it has no inherent capability to produce the executables hence external C compiler and libraries are needed.There is a compation project WHPC which provides a complete self-contained environment for compiling and running the high performance numeric codes on 32 and 64 bit Windows. Being an independent project it is however designed with Finita in mind: WHPC and Finita together constitute a complete build and run environment on Windows for both sequential and parallel execution.

WHPC home page is: http://whpc.sourceforge.net/ 

Any samples?
------------

A few working examples can be found in the \sample subdirectory of the installation.

Provided that both Finita and WHPC are successfully installed on the system the instruction for building a sample Cavity problem employing sequential debugging version of MUMPS linear solver is as follows:

1) Generate source code cavity.auto.h and cavity.auto.c

> finitac cavity.rb

2) Build executable cavity.exe

> %CC% -g -o cavity %MUMPS_DSG_CPPFLAGS% cavity.c cavity.auto.c %MUMPS_DSG_LDFLAGS% %MUMPS_DSG_LDLIBS%

3) Perform a test run

> cavity.exe

For more information on WHPC refer to the respective documentation.

3rd parties
-----------

This installation ships an unmodified Ruby runtime from the RubyInstaller project. The installer itself is built by the Inno Setup distribution generator.

RubyInstaller home page: http://rubyinstaller.org
Inno Setup home page: http://www.jrsoftware.org/isinfo.php

THE END
=======

That's all for now, folks.
Happy number crunching!

Oleg A. Khlybov <fougas@mail.ru>
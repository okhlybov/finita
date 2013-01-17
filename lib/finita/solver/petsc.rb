module Finita


class Solver::PETSc < Solver::Matrix
  class Code < Solver::Matrix::Code
    def write_defs(stream)
      super
      solver.linear? ? write_slae_defs(stream) : write_snae_defs(stream)
    end
    def write_slae_defs(stream)
      stream << %$
        #include "petscksp.h"
      $
    end
    def write_snae_defs(stream)
      stream << %$
        #include "petscsnes.h"
      $
    end
  end # Code
  def write_initializer(stream)
    stream << %${PetscErrorCode ierr = PetscInitialize(&argc, &argv, PETSC_NULL, PETSC_NULL); CHKERRQ(ierr);}$
    super
  end
end # PETSc


end # Finita
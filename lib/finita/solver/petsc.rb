module Finita


class Solver::PETSc < Solver::Matrix
  StaticCode = Class.new(DataStructBuilder::Code) do
    def write_intf(stream)
      super
      stream << %$
        #include "petsc.h"
        static PetscErrorCode #{setup}(int* argc, char*** argv) {
          PetscErrorCode ierr;
          FINITA_ENTER;
          ierr = PetscInitialize(argc, argv, PETSC_NULL, PETSC_NULL); CHKERRQ(ierr);
          FINITA_RETURN(0);
        }
        static PetscErrorCode #{cleanup}(void) {
          PetscErrorCode ierr;
          FINITA_ENTER;
          ierr = PetscFinalize(); CHKERRQ(ierr);
          FINITA_RETURN(0);
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{StaticCode.setup}(&argc, &argv);$
    end
    def write_finalizer(stream)
      stream << %$#{StaticCode.cleanup}();$
    end
  end.new("PETSc") # StaticCode
  def initialize(*args)
    super
    raise "unsupported environment" unless environment.seq? or environment.mpi?
  end
  def code(system_code)
    system_code.problem_code.initializer_codes << StaticCode
    system_code.problem_code.finalizer_codes << StaticCode
    super
  end
  class Code < Solver::Matrix::Code
    def initialize(*args)
      super
      system_code.initializer_codes << self
      system_code.finalizer_codes << self
    end
    def write_defs(stream)
      stream << %$static PetscErrorCode #{petscSetup}(void);$;
      super
      if mpi?
        mt = "MATMPIAIJ"
        vt = "VECMPI"
        preallocate_stmt = %${
          PetscInt *dnz, *onz;
          FINITA_ENTER;
          dnz = (PetscInt*)#{calloc}(size, sizeof(PetscInt)); #{assert}(dnz);
          onz = (PetscInt*)#{calloc}(size, sizeof(PetscInt)); #{assert}(onz);
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          while(#{SparsityPatternCode.itHasNext}(&it)) {
            size_t row, column;
            #{NodeCoordCode.type} coord = #{SparsityPatternCode.itNext}(&it);
            row = #{mapper_code.index}(coord.row);
            #{assert}(first <= row && row <= last);
            column = #{mapper_code.index}(coord.column);
            if(first <= column && column <= last) ++dnz[row - first]; else ++onz[row - first];
          }
          ierr = MatMPIAIJSetPreallocation(#{matrix}, 0, dnz, 0, onz); CHKERRQ(ierr);
          #{free}(dnz);
          #{free}(onz);
          FINITA_LEAVE;
        }$
      else
        mt = "MATSEQAIJ"
        vt = "VECSEQ"
        preallocate_stmt = %${
          PetscInt *nnz;
          FINITA_ENTER;
          nnz = (PetscInt*)#{calloc}(size, sizeof(PetscInt)); #{assert}(nnz);
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          while(#{SparsityPatternCode.itHasNext}(&it)) {
            size_t row, column;
            #{NodeCoordCode.type} coord = #{SparsityPatternCode.itNext}(&it);
            row = #{mapper_code.index}(coord.row);
            #{assert}(first <= row && row <= last);
            column = #{mapper_code.index}(coord.column);
            ++nnz[row - first];
          }
          ierr = MatSeqAIJSetPreallocation(#{matrix}, 0, nnz); CHKERRQ(ierr);
          #{free}(nnz);
          FINITA_LEAVE;
        }$
      end
      if @solver.linear?
        stream << %$static KSP #{ksp};$
        solver_setup_stmt = %$
          ierr = KSPCreate(PETSC_COMM_WORLD, &#{ksp}); CHKERRQ(ierr);
          ierr = KSPSetFromOptions(#{ksp}); CHKERRQ(ierr);
          ierr = KSPSetOperators(#{ksp}, #{matrix}, #{matrix}, 0); CHKERRQ(ierr);
        $
      else
        stream << %$static SNES #{snes};$
        solver_setup_stmt = %$
          ierr = SNESCreate(PETSC_COMM_WORLD, &#{snes}); CHKERRQ(ierr);
          ierr = SNESSetFromOptions(#{snes}); CHKERRQ(ierr);
        $
      end
      stream << %$
        static Mat #{matrix};
        static Vec #{vector};
        static size_t #{matrixSize}, #{vectorSize};
        static PetscInt *#{matrixRows}, *#{matrixColumns}, *#{vectorIndices};
        static PetscScalar* #{matrixValues}, *#{vectorValues};
        static PetscErrorCode #{petscSetup}(void) {
          PetscErrorCode ierr;
          #{SparsityPatternCode.it} it;
          size_t size, index, first, last;
          FINITA_ENTER;
          size = #{decomposer_code.indexCount}();
          first = #{decomposer_code.firstIndex}();
          last = #{decomposer_code.lastIndex}();
          ierr = MatCreate(PETSC_COMM_WORLD, &#{matrix}); CHKERRQ(ierr);
          ierr = MatSetSizes(#{matrix}, size, #{mapper_code.size}(), PETSC_DECIDE, PETSC_DECIDE); CHKERRQ(ierr);
          ierr = MatSetType(#{matrix}, #{mt}); CHKERRQ(ierr);
          #{preallocate_stmt};
          #ifndef NDEBUG
          {
            PetscInt petsc_first, petsc_last;
            MatGetOwnershipRange(#{matrix}, &petsc_first, &petsc_last);
            #{assert}(first == petsc_first);
            #{assert}(last == petsc_last-1);
          }
          #endif
          ierr = VecCreate(PETSC_COMM_WORLD, &#{vector}); CHKERRQ(ierr);
          ierr = VecSetType(#{vector}, #{vt}); CHKERRQ(ierr);
          ierr = VecSetSizes(#{vector}, size, PETSC_DECIDE); CHKERRQ(ierr);
          #{solver_setup_stmt};
          index = 0;
          #{matrixSize} = #{SparsityPatternCode.size}(&#{sparsity});
          #{matrixRows} = (PetscInt*)#{malloc}(#{matrixSize}*sizeof(PetscInt)); #{assert}(#{matrixRows});
          #{matrixColumns} = (PetscInt*)#{malloc}(#{matrixSize}*sizeof(PetscInt)); #{assert}(#{matrixColumns});
          #{matrixValues} = (PetscScalar*)#{malloc}(#{matrixSize}*sizeof(PetscScalar)); #{assert}(#{matrixValues});
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          while(#{SparsityPatternCode.itHasNext}(&it)) {
            #{NodeCoordCode.type} coord = #{SparsityPatternCode.itNext}(&it);
            #{matrixRows}[index] = #{mapper_code.index}(coord.row);
            #{matrixColumns}[index] = #{mapper_code.index}(coord.column);
            ++index;
          }
          #{assert}(index == #{matrixSize});
          #{vectorSize} = size;
          #{vectorIndices} = (PetscInt*)#{malloc}(#{vectorSize}*sizeof(PetscInt)); #{assert}(#{vectorIndices});
          #{vectorValues} = (PetscScalar*)#{malloc}(#{vectorSize}*sizeof(PetscScalar)); #{assert}(#{vectorValues});
          for(index = first; index <= last; ++index) {
            #{vectorIndices}[index - first] = index;
          }
          FINITA_RETURN(0);
        }
      $
      @solver.linear? ? write_solve_linear(stream) : write_solve_nonlinear(stream)
      stream << %$
        void #{system_code.solve}(void) {
          #{invoke}();
        }
      $
    end
    def write_solve_linear(stream)
      stream << %$
        static PetscErrorCode #{invoke}(void) {
          size_t index;
          PetscErrorCode ierr;
          FINITA_ENTER;
          for(index = 0; index < #{matrixSize}; ++index) {
            #{matrixValues}[index] = #{lhs_code.evaluate}(#{mapper_code.node}(#{matrixRows}[index]), #{mapper_code.node}(#{matrixColumns}[index]));
          }
          ierr = MatSetValues(#{matrix}, #{matrixSize}, #{matrixRows}, #{matrixSize}, #{matrixColumns}, #{matrixValues}, INSERT_VALUES); CHKERRQ(ierr);
          ierr = MatAssemblyBegin(#{matrix}, MAT_FINAL_ASSEMBLY); CHKERRQ(ierr);
          ierr = MatAssemblyEnd(#{matrix}, MAT_FINAL_ASSEMBLY); CHKERRQ(ierr);
          ierr = MatSetOption(#{matrix}, MAT_NEW_NONZERO_ALLOCATION_ERR, PETSC_TRUE); CHKERRQ(ierr);
          ierr = MatSetOption(#{matrix}, MAT_NEW_NONZERO_LOCATION_ERR, PETSC_TRUE); CHKERRQ(ierr);
          for(index = 0; index < #{vectorSize}; ++index) {
            #{vectorValues}[index] = -#{rhs_code.evaluate}(#{mapper_code.node}(#{vectorIndices}[index]));
          }
          ierr = VecSetValues(#{vector}, #{vectorSize}, #{vectorIndices}, #{vectorValues}, INSERT_VALUES); CHKERRQ(ierr);
          ierr = VecAssemblyBegin(#{vector}); CHKERRQ(ierr);
          ierr = VecAssemblyEnd(#{vector}); CHKERRQ(ierr);
          ierr = KSPSolve(#{ksp}, #{vector}, #{vector});
          ierr = VecGetValues(#{vector}, #{vectorSize}, #{vectorIndices}, #{vectorValues}); CHKERRQ(ierr);
          for(index = 0; index < #{vectorSize}; ++index) {
            #{mapper_code.indexSet}(#{vectorIndices}[index], #{vectorValues}[index]);
          }
          #{decomposer_code.synchronizeUnknowns}();
          FINITA_RETURN(0);
        }
      $
    end
    def write_solve_nonlinear(stream)
    end
    def write_setup_body(stream)
      super
      stream << %$#{petscSetup}();$
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
    def write_finalizer(stream)
      stream << %$#{cleanup}();$
    end
  end # Code
end # PETSc


end # Finita
module Finita


class Solver::PETSc < Solver::Matrix
  StaticCode = Class.new(Finita::Code) do
    def write_decls(stream)
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
        typedef struct {
          PetscInt row, column;
        } FinitaRowColumn;
        static int FinitaRowOrientedCompare(const void* l, const void* r) {
          const FinitaRowColumn* lt = (FinitaRowColumn*)l;
          const FinitaRowColumn* rt = (FinitaRowColumn*)r;
          if(lt->row < rt->row)
            return -1;
          else if(lt->row > rt->row)
            return +1;
          else if(lt->column < rt->column)
            return -1;
          else if(lt->column > rt->column)
            return +1;
          else
            return 0;
        }
        static int FinitaColumnOrientedCompare(const void* l, const void* r) {
          FinitaRowColumn* lt = (FinitaRowColumn*)l;
          FinitaRowColumn* rt = (FinitaRowColumn*)r;
          if(lt->column < rt->column)
            return -1;
          else if(lt->column > rt->column)
            return +1;
          else if(lt->row < rt->row)
            return -1;
          else if(lt->row > rt->row)
            return +1;
          else
            return 0;
        }
        static void FinitaRowColumnSort(FinitaRowColumn* rc, size_t count, int row_first) {
          #{assert}(rc);
          #{assert}(count > 0);
          qsort(rc, count, sizeof(FinitaRowColumn), row_first ? FinitaRowOrientedCompare : FinitaColumnOrientedCompare);
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{StaticCode.setup}(&argc, &argv);$
    end
    def write_finalizer(stream)
      stream << %$#{StaticCode.cleanup}();$
    end
  end.new(:FinitaPETSc) # StaticCode
  # TODO : only the most common are listed; add more types
  Solvers = {
      :Richardson => :KSPRICHARDSON, :Chebyshev => :KSPCHEBYSHEV, :CG => :KSPCG, :GMRES => :KSPGMRES, :FGMRES => :KSPFGMRES,
      :TCQMR => :KSPTCQMR, :TFQMR => :KSPTFQMR, :CGS => :KSPCGS, :CR => :KSPCR, :QCG => :KSPQCG, :BiCG => :KSPBICG,
      :MINRES => :KSPMINRES, :GCR => :KSPGCR
  }
  def solver=(s)
    raise "unsupported solver type #{s}" if Solvers[s].nil?
    super
  end
  # TODO : only the most common are listed; add more types
  Preconditioners = {
      nil => :PCNONE, :Jacobi => :PCJACOBI, :SOR => :PCSOR, :LU => :PCLU, :ILU => :PCILU, :Cholesky => :PCCHOLESKY,
      :BJacobi => :PCBJACOBI, :PBJacobi => :PCPBJACOBI
  }
  def preconditioner=(p)
    raise "unsupported preconditioner type #{p}" if Preconditioners[p].nil?
    super
  end
  attr_accessor :purge_sparsity # Boolean to purge sparsity pattern(s) after solver initialization to save (a lot) of heap memory
  attr_accessor :retain_solution # Boolean to retain the solution result and use it as an initial guess in subsequent computations
  def initialize(*args)
    super
    self.solver = :GMRES
    self.preconditioner = :ILU
    self.retain_solution = true
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
      stream << %$static PetscErrorCode #{petscSetup}(void);$
      super
      stream << %$
        static PetscErrorCode #{jacobianEvaluator}(SNES, Vec, Mat, Mat, void*);
        static PetscErrorCode #{residualEvaluator}(SNES, Vec, Vec, void*);
      $ if !@solver.linear?
      stream << %$
        static Mat #{matrix};
        static Vec #{vector}, #{solution};
        #define #{retainSolution} #{@solver.retain_solution ? 1 : 0}
        static size_t #{matrixSize}, #{vectorSize};
        static FinitaRowColumn* #{matrixRC};
        static PetscInt *#{vectorIndices};
        static PetscErrorCode #{petscSetup}(void) {
          PetscErrorCode ierr;
          #{SparsityPatternCode.it} it;
          size_t size, index, first, last;
          MatType mat_type;
          int preallocated = 1;
          FINITA_ENTER;
          size = #{decomposer_code.indexCount}();
          first = #{decomposer_code.firstIndex}();
          last = #{decomposer_code.lastIndex}();
          ierr = MatCreate(PETSC_COMM_WORLD, &#{matrix}); CHKERRQ(ierr);
          ierr = MatSetSizes(#{matrix}, size, size, PETSC_DECIDE, PETSC_DECIDE); CHKERRQ(ierr);
          ierr = MatSetFromOptions(#{matrix}); CHKERRQ(ierr);
          ierr = MatGetType(#{matrix}, &mat_type); CHKERRQ(ierr);
          if(strcmp(mat_type, MATSEQAIJ) == 0) {
            PetscInt *nnz;
            FINITA_ENTER;
            nnz = (PetscInt*)#{calloc}(size, sizeof(PetscInt)); #{assert}(nnz);
            #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
            while(#{SparsityPatternCode.itMove}(&it)) {
              size_t row;
              #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
              row = #{mapper_code.index}(coord.row);
              #{assert}(first <= row && row <= last);
              ++nnz[row - first];
            }
            ierr = MatSeqAIJSetPreallocation(#{matrix}, PETSC_DEFAULT, nnz); CHKERRQ(ierr);
            #{free}(nnz);
            FINITA_LEAVE;
          } else
          if(strcmp(mat_type, MATMPIAIJ) == 0) {
            PetscInt *dnz, *onz;
            FINITA_ENTER;
            dnz = (PetscInt*)#{calloc}(size, sizeof(PetscInt)); #{assert}(dnz);
            onz = (PetscInt*)#{calloc}(size, sizeof(PetscInt)); #{assert}(onz);
            #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
            while(#{SparsityPatternCode.itMove}(&it)) {
              size_t row, column;
              #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
              row = #{mapper_code.index}(coord.row);
              #{assert}(first <= row && row <= last);
              column = #{mapper_code.index}(coord.column);
              if(first <= column && column <= last) ++dnz[row - first]; else ++onz[row - first];
            }
            ierr = MatMPIAIJSetPreallocation(#{matrix}, PETSC_DEFAULT, dnz, PETSC_DEFAULT, onz); CHKERRQ(ierr);
            #{free}(dnz);
            #{free}(onz);
            FINITA_LEAVE;
          } else {
            preallocated = 0;
            ierr = MatSetUp(#{matrix}); CHKERRQ(ierr);
          }
          if(preallocated) {
            ierr = MatSetOption(#{matrix}, MAT_NEW_NONZERO_LOCATION_ERR, PETSC_TRUE); CHKERRQ(ierr);
            ierr = MatSetOption(#{matrix}, MAT_NEW_NONZERO_ALLOCATION_ERR, PETSC_TRUE); CHKERRQ(ierr);
          }
          #ifndef NDEBUG
          {
            PetscInt petsc_first, petsc_last, petsc_cols, petsc_rows;
            ierr = MatGetOwnershipRange(#{matrix}, &petsc_first, &petsc_last); CHKERRQ(ierr);
            #{assert}(first == petsc_first);
            #{assert}(last == petsc_last-1);
            ierr = MatGetSize(#{matrix}, &petsc_rows, &petsc_cols); CHKERRQ(ierr);
            #{assert}(petsc_rows == petsc_cols);
            #{assert}(petsc_rows == #{mapper_code.size}());
          }
          #endif
          ierr = VecCreate(PETSC_COMM_WORLD, &#{vector}); CHKERRQ(ierr);
          ierr = VecSetSizes(#{vector}, size, PETSC_DECIDE); CHKERRQ(ierr);
          ierr = VecSetFromOptions(#{vector}); CHKERRQ(ierr);
          if(#{retainSolution}) {
            ierr = VecDuplicate(#{vector}, &#{solution}); CHKERRQ(ierr);
          }
          {
            index = 0;
            #{matrixSize} = #{SparsityPatternCode.size}(&#{sparsity});
            #{matrixRC} = (FinitaRowColumn*)#{malloc}(#{matrixSize}*sizeof(FinitaRowColumn)); #{assert}(#{matrixRC});
            #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
            while(#{SparsityPatternCode.itMove}(&it)) {
              #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
              #{matrixRC}[index].row = #{mapper_code.index}(coord.row);
              #{matrixRC}[index].column = #{mapper_code.index}(coord.column);
              ++index;
            }
            #{assert}(index == #{matrixSize});
            FinitaRowColumnSort(#{matrixRC}, #{matrixSize}, 1);
          }
          #{vectorSize} = size;
          #{vectorIndices} = (PetscInt*)#{malloc}(#{vectorSize}*sizeof(PetscInt)); #{assert}(#{vectorIndices});
          for(index = first; index <= last; ++index) {
            #{vectorIndices}[index - first] = index;
          }
          #{SparsityPatternCode.purge('&'+sparsity) if @solver.purge_sparsity};
          FINITA_RETURN(0);
        }
      $
      stream << %$
        #ifndef NDEBUG
          static void #{checkPivot}(PetscScalar* values, size_t index, size_t count) {
            FinitaNode rn = #{mapper_code.node}(#{matrixRC}[index].row);
            if(#{matrixRC}[index].row == #{matrixRC}[index].column && values[count] == 0.0) {
              #{StringCode.type} out;
              #{StringCode.ctor}(&out, NULL);
              #{StringCode.pushFormat}(&out, "*** WARNING: zero pivot detected for %s(%d,%d,%d)\\n", #{mapper_code.fieldName}[rn.field], rn.x, rn.y, rn.z);
              fputs(#{StringCode.chars}(&out), stderr);
              #{StringCode.dtor}(&out);
            }
          }
        #endif
      $
      @solver.linear? ? write_solve_linear(stream) : write_solve_nonlinear(stream)
      stream << %$
        int #{system_code.solve}(void) {
          return #{invoke}();
        }
      $
    end
    def write_solve_linear(stream)
      stream << %$
        static PetscErrorCode #{invoke}(void) {
          size_t index, count;
          PetscScalar* values;
          PetscInt row;
          PetscInt* columns;
          PetscErrorCode ierr;
          KSPConvergedReason reason;
          KSP ksp;
          PC pc;
          FINITA_ENTER;
          values = (PetscScalar*)#{malloc}(#{matrixSize}*sizeof(PetscScalar)); #{assert}(values);
          #define #{_FAST} // Rig for fast values computation
#ifndef #{_FAST}
          columns = (PetscInt*)#{malloc}(#{matrixSize}*sizeof(PetscInt)); #{assert}(columns);
          for(index = count = 0, row = #{matrixRC}[index].row; index < #{matrixSize}; ++index) {
            /* assuming RC is in the row-first form */
            #{assert}(#{matrixRC}[index].row >= row);
            if(#{matrixRC}[index].row > row) {
              ierr = MatSetValues(#{matrix}, 1, &row, count, columns, values, INSERT_VALUES); CHKERRQ(ierr);
              row = #{matrixRC}[index].row;
              count = 0;
            }
            #{assert}(count < #{matrixSize});
            values[count] = #{lhs_code.evaluate}(#{mapper_code.node}(#{matrixRC}[index].row), #{mapper_code.node}(#{matrixRC}[index].column));
            #ifndef NDEBUG
              #{checkPivot}(values, index, count);
            #endif
            columns[count] = #{matrixRC}[index].column;
            ++count;
          }
          ierr = MatSetValues(#{matrix}, 1, &row, count, columns, values, INSERT_VALUES); CHKERRQ(ierr);
          #{free}(columns);
#else
          #{lhs_code.compute}(values, #{matrixSize});
          for(index = 0; index < #{lhs_code.indexCount}; ++index) {
            ierr = MatSetValue(#{matrix}, #{lhs_code.indices}[index].row, #{lhs_code.indices}[index].column, values[index], INSERT_VALUES); CHKERRQ(ierr);
          }
#endif
          ierr = MatAssemblyBegin(#{matrix}, MAT_FINAL_ASSEMBLY); CHKERRQ(ierr);
            #{assert}(#{matrixSize} >= #{vectorSize});
#ifndef #{_FAST}
            for(index = 0; index < #{vectorSize}; ++index) {
              values[index] = -#{rhs_code.evaluate}(#{mapper_code.node}(#{vectorIndices}[index]));
            }
#else
            #{rhs_code.compute}(values, #{vectorSize});
#endif
            ierr = VecSetValues(#{vector}, #{vectorSize}, #{vectorIndices}, values, INSERT_VALUES); CHKERRQ(ierr);
            ierr = VecAssemblyBegin(#{vector}); CHKERRQ(ierr);
              ierr = KSPCreate(PETSC_COMM_WORLD, &ksp); CHKERRQ(ierr);
              ierr = KSPSetType(ksp, #{Solvers[@solver.solver]}); CHKERRQ(ierr);
              ierr = KSPGetPC(ksp, &pc); CHKERRQ(ierr);
              ierr = PCSetType(pc, #{Preconditioners[@solver.preconditioner]}); CHKERRQ(ierr);
              ierr = KSPSetTolerances(ksp, #{@solver.relative_tolerance}, #{@solver.absolute_tolerance}, PETSC_DEFAULT, #{@solver.max_steps}); CHKERRQ(ierr);
              if(#{retainSolution}) {
                ierr = KSPSetInitialGuessNonzero(ksp, PETSC_TRUE); CHKERRQ(ierr);
              } else {
                ierr = VecDuplicate(#{vector}, &#{solution}); CHKERRQ(ierr);
                ierr = VecZeroEntries(#{solution}); CHKERRQ(ierr);
              }
              ierr = KSPSetFromOptions(ksp); CHKERRQ(ierr);
              ierr = KSPSetOperators(ksp, #{matrix}, #{matrix}); CHKERRQ(ierr);
            ierr = VecAssemblyEnd(#{vector}); CHKERRQ(ierr);
          ierr = MatAssemblyEnd(#{matrix}, MAT_FINAL_ASSEMBLY); CHKERRQ(ierr);
          ierr = KSPSolve(ksp, #{vector}, #{solution}); CHKERRQ(ierr);
          ierr = KSPGetConvergedReason(ksp, &reason); CHKERRQ(ierr);
          ierr = KSPDestroy(&ksp); CHKERRQ(ierr);
          ierr = VecGetValues(#{solution}, #{vectorSize}, #{vectorIndices}, values); CHKERRQ(ierr);
          for(index = 0; index < #{vectorSize}; ++index) {
            #{mapper_code.indexSet}(#{vectorIndices}[index], values[index]);
          }
          #{decomposer_code.synchronizeUnknowns}();
          if(!#{retainSolution}) {
            ierr = VecDestroy(&#{solution}); CHKERRQ(ierr);
          }
          #{free}(values);
          FINITA_RETURN(reason);
        }
      $
    end
    def write_solve_nonlinear(stream)
      stream << %$
        static PetscErrorCode #{unknowns2Vector}(Vec x) {
          PetscErrorCode ierr;
          PetscScalar* values;
          PetscInt size;
          size_t index, first;
          FINITA_ENTER;
          first = #{decomposer_code.firstIndex}();
          ierr = VecGetLocalSize(x, &size); CHKERRQ(ierr);
          #{assert}(#{decomposer_code.indexCount}() == size);
          #{assert}(#{decomposer_code.lastIndex}() == first + size - 1);
          ierr = VecGetArray(x, &values); CHKERRQ(ierr);
          for(index = 0; index < size; ++index) {
            values[index] = #{mapper_code.indexGet}(index + first);
          }
          ierr = VecRestoreArray(x, &values); CHKERRQ(ierr);
          FINITA_RETURN(0);
        }
        static PetscErrorCode #{vector2Unknowns}(Vec x) {
          PetscErrorCode ierr;
          PetscScalar* values;
          PetscInt size;
          size_t index, first;
          FINITA_ENTER;
          first = #{decomposer_code.firstIndex}();
          ierr = VecGetLocalSize(x, &size); CHKERRQ(ierr);
          #{assert}(#{decomposer_code.indexCount}() == size);
          #{assert}(#{decomposer_code.lastIndex}() == first + size - 1);
          ierr = VecGetArray(x, &values); CHKERRQ(ierr);
          for(index = 0; index < size; ++index) {
            #{mapper_code.indexSet}(index + first, values[index]);
          }
          ierr = VecRestoreArray(x, &values); CHKERRQ(ierr);
          #{decomposer_code.synchronizeUnknowns}();
          FINITA_RETURN(0);
        }
        static PetscErrorCode #{residualEvaluator}(SNES snes, Vec x, Vec f, void* ctx) {
          PetscErrorCode ierr;
          size_t index;
          #ifndef NDEBUG
            PetscInt xsize;
          #endif
          PetscInt fsize;
          PetscScalar* values;
          FINITA_ENTER;
          #ifndef NDEBUG
            ierr = VecGetSize(x, &xsize); CHKERRQ(ierr);
          #endif
          ierr = VecGetSize(f, &fsize); CHKERRQ(ierr);
          #{assert}(fsize == xsize);
          ierr = #{vector2Unknowns}(x); CHKERRQ(ierr);
          values = (PetscScalar*)#{malloc}(#{vectorSize}*sizeof(PetscScalar)); #{assert}(values);
          for(index = 0; index < #{vectorSize}; ++index) {
            values[index] = #{residual_code.evaluate}(#{mapper_code.node}(#{vectorIndices}[index]));
          }
          ierr = VecSetValues(f, #{vectorSize}, #{vectorIndices}, values, INSERT_VALUES); CHKERRQ(ierr);
          #{free}(values);
          ierr = VecAssemblyBegin(f); CHKERRQ(ierr);
          ierr = VecAssemblyEnd(f); CHKERRQ(ierr);
          FINITA_RETURN(0);
        }
        static PetscErrorCode #{jacobianEvaluator}(SNES snes, Vec x, Mat A, Mat B, void* ctx) {
          PetscErrorCode ierr;
          size_t index, count;
          PetscScalar* values;
          PetscInt row;
          PetscInt* columns;
          FINITA_ENTER;
          ierr = #{vector2Unknowns}(x); CHKERRQ(ierr);
          values = (PetscScalar*)#{malloc}(#{matrixSize}*sizeof(PetscScalar)); #{assert}(values);
          columns = (PetscInt*)#{malloc}(#{matrixSize}*sizeof(PetscInt)); #{assert}(columns);
          #ifndef NDEBUG
          {
            PetscInt first, last;
            ierr = MatGetOwnershipRange(A, &first, &last);
            #{assert}(#{decomposer_code.firstIndex}() == first);
            #{assert}(#{decomposer_code.lastIndex}() == last - 1);
          }
          #endif
          for(index = count = 0, row = #{matrixRC}[index].row; index < #{matrixSize}; ++index) {
            /* assuming RC is in the row-first form */
            #{assert}(#{matrixRC}[index].row >= row);
            if(#{matrixRC}[index].row > row) {
              ierr = MatSetValues(#{matrix}, 1, &row, count, columns, values, INSERT_VALUES); CHKERRQ(ierr);
              row = #{matrixRC}[index].row;
              count = 0;
            }
            #{assert}(count < #{matrixSize});
            values[count] = #{jacobian_code.evaluate}(#{mapper_code.node}(#{matrixRC}[index].row), #{mapper_code.node}(#{matrixRC}[index].column));
            #ifndef NDEBUG
              #{checkPivot}(values, index, count);
            #endif
            columns[count] = #{matrixRC}[index].column;
            ++count;
          }
          ierr = MatSetValues(A, 1, &row, count, columns, values, INSERT_VALUES); CHKERRQ(ierr);
          ierr = MatAssemblyBegin(A, MAT_FINAL_ASSEMBLY); CHKERRQ(ierr);
          ierr = MatAssemblyEnd(A, MAT_FINAL_ASSEMBLY); CHKERRQ(ierr);
          #{free}(columns);
          #{free}(values);
          FINITA_RETURN(0);
        }
        static PetscErrorCode #{invoke}(void) {
          PetscErrorCode ierr;
          SNESConvergedReason reason;
          Vec vector;
          SNES snes;
          KSP ksp;
          PC pc;
          FINITA_ENTER;
          ierr = #{unknowns2Vector}(#{vector}); CHKERRQ(ierr);
          ierr = VecDuplicate(#{vector}, &vector); CHKERRQ(ierr);
          ierr = SNESCreate(PETSC_COMM_WORLD, &snes); CHKERRQ(ierr);
          ierr = SNESGetKSP(snes, &ksp); CHKERRQ(ierr);
          ierr = KSPSetType(ksp, #{Solvers[@solver.solver]}); CHKERRQ(ierr);
          ierr = KSPGetPC(ksp, &pc); CHKERRQ(ierr);
          ierr = PCSetType(pc, #{Preconditioners[@solver.preconditioner]}); CHKERRQ(ierr);
          ierr = SNESSetTolerances(snes, #{@solver.absolute_tolerance}, #{@solver.relative_tolerance}, PETSC_DEFAULT, #{@solver.max_steps}, PETSC_DEFAULT); CHKERRQ(ierr);
          ierr = SNESSetFromOptions(snes); CHKERRQ(ierr);
          ierr = SNESSetJacobian(snes, #{matrix}, #{matrix}, #{jacobianEvaluator}, PETSC_NULL); CHKERRQ(ierr);
          ierr = SNESSetFunction(snes, vector, #{residualEvaluator}, PETSC_NULL); CHKERRQ(ierr);
          ierr = SNESSolve(snes, PETSC_NULL, #{vector}); CHKERRQ(ierr);
          ierr = SNESGetConvergedReason(snes, &reason); CHKERRQ(ierr);
          ierr = SNESDestroy(&snes); CHKERRQ(ierr);
          ierr = VecDestroy(&vector); CHKERRQ(ierr);
          ierr = #{vector2Unknowns}(#{vector}); CHKERRQ(ierr);
          FINITA_RETURN(reason);
        }
      $
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
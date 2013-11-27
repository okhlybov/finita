module Finita


class Solver::LIS < Solver::Matrix
  StaticCode = Class.new(DataStructBuilder::Code) do
    def write_defs(stream)
      super
      stream << %$
        #include "lis.h"
      $
    end
    def write_initializer(stream)
      stream << %${
        LIS_INT ierr;
        ierr = lis_initialize(&argc, &argv); CHKERR(ierr);
      }$
    end
    def write_finalizer(stream)
      stream << %${
        LIS_INT ierr;
        ierr = lis_finalize(); CHKERR(ierr);
      }$
    end
  end.new("LIS") # StaticCode
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
      @have_array = mpi? && !@solver.linear?
      @numeric_array_code = NumericArrayCode[system_code.result] if @have_array
      @comm = mpi? ? :MPI_COMM_WORLD : 0
    end
    def entities
      @entities.nil? ? @entities = super + [@numeric_array_code].compact : @entities
    end
    def write_setup_body(stream)
      super
      stream << %$#{@numeric_array_code.ctor}(&#{array}, #{mapper_code.size}());$ if @have_array
    end
    def write_cleanup_body(stream)
      super
      stream << %$#{@numeric_array_code.dtor}(&#{array});$ if @have_array
    end
    def write_defs(stream)
      stream << %$static #{@numeric_array_code.type} #{array};$ if @have_array
      super
      stream << %$
        static void #{collectNNZ}(LIS_INT** nnz) {
          size_t first_row;
          #{SparsityPatternCode.it} it;
          FINITA_ENTER;
          *nnz = (LIS_INT*) #{calloc}(#{decomposer_code.indexCount}(), sizeof(LIS_INT)); #{assert}(*nnz);
          first_row = #{decomposer_code.firstIndex}();
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          while(#{SparsityPatternCode.itHasNext}(&it)) {
            ++((*nnz)[#{mapper_code.index}(#{SparsityPatternCode.itNext}(&it).row) - first_row]);
          }
          FINITA_LEAVE;
        }
      $
      @solver.linear? ? write_solve_linear(stream) : write_solve_nonlinear(stream)
    end
    def write_solve_linear(stream)
      stream << %$
        void #{system_code.solve}(void) {
          int ierr;
          size_t first, last, index;
          #{SparsityPatternCode.it} it;
          LIS_SOLVER solver;
          LIS_MATRIX A;
          LIS_VECTOR b, x;
          LIS_INT* nnz;
          FINITA_ENTER;
          ierr = lis_solver_create(&solver); CHKERR(ierr);
          ierr = lis_solver_set_option("-initx_zeros false", solver); CHKERR(ierr);
          #ifndef NDEBUG
            ierr = lis_solver_set_option("-print mem", solver); CHKERR(ierr);
          #endif
          ierr = lis_solver_set_optionC(solver); CHKERR(ierr);
          ierr = lis_matrix_create(#{@comm}, &A); CHKERR(ierr);
          ierr = lis_matrix_set_size(A, #{decomposer_code.indexCount}(), 0); CHKERR(ierr);
          ierr = lis_vector_create(#{@comm}, &x); CHKERR(ierr);
          ierr = lis_vector_set_size(x, #{decomposer_code.indexCount}(), 0); CHKERR(ierr);
          ierr = lis_vector_duplicate(x, &b); CHKERR(ierr);
          first = #{decomposer_code.firstIndex}();
          last = #{decomposer_code.lastIndex}();
          #ifndef NDEBUG
          {
            LIS_INT is, ie;
            ierr = lis_vector_get_range(b, &is, &ie); CHKERR(ierr);
            FINITA_ASSERT(first == is && last == ie-1);
            ierr = lis_vector_get_range(x, &is, &ie); CHKERR(ierr);
            FINITA_ASSERT(first == is && last == ie-1);
          }
          #endif
          #{collectNNZ}(&nnz);
          ierr = lis_matrix_malloc(A, 0, nnz); CHKERR(ierr);
          #{free}(nnz);
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          while(#{SparsityPatternCode.itHasNext}(&it)) {
            #{NodeCoordCode.type} coord;
            coord = #{SparsityPatternCode.itNext}(&it);
            ierr = lis_matrix_set_value(LIS_INS_VALUE, #{mapper_code.index}(coord.row), #{mapper_code.index}(coord.column), #{lhs_code.evaluate}(coord.row, coord.column), A); CHKERR(ierr);
          }
          ierr = lis_matrix_assemble(A); CHKERR(ierr);
          for(index = first; index <= last; ++index) {
            ierr = lis_vector_set_value(LIS_INS_VALUE, index, -#{rhs_code.evaluate}(#{mapper_code.node}(index)), b); CHKERR(ierr);
            ierr = lis_vector_set_value(LIS_INS_VALUE, index, #{mapper_code.indexGet}(index), x); CHKERR(ierr);
          }
          ierr = lis_solve(A, b, x, solver); CHKERR(ierr);
          for(index = first; index <= last; ++index) {
            LIS_SCALAR value;
            ierr = lis_vector_get_value(x, index, &value); CHKERR(ierr);
            #{mapper_code.indexSet}(index, value);
          }
          #{decomposer_code.synchronizeUnknowns}();
          ierr = lis_solver_destroy(solver); CHKERR(ierr);
          ierr = lis_matrix_destroy(A); CHKERR(ierr);
          ierr = lis_vector_destroy(x); CHKERR(ierr);
          ierr = lis_vector_destroy(b); CHKERR(ierr);
          FINITA_LEAVE;
        }
      $
    end
    def write_solve_nonlinear(stream)
      abs = CAbs[system_code.result]
      stream << %$
        void #{system_code.solve}(void) {
          int stop, step = 0;
          int ierr;
          size_t first, last, index;
          #{SparsityPatternCode.it} it;
          LIS_SOLVER solver;
          LIS_MATRIX A;
          LIS_VECTOR b, x;
          LIS_INT* nnz;
          FINITA_ENTER;
          first = #{decomposer_code.firstIndex}();
          last = #{decomposer_code.lastIndex}();
          #{collectNNZ}(&nnz);
          do {
            double norm, base = 0, delta = 0; /* TODO : complex */
            ierr = lis_solver_create(&solver); CHKERR(ierr);
            #ifndef NDEBUG
              ierr = lis_solver_set_option("-print mem", solver); CHKERR(ierr);
            #endif
            ierr = lis_solver_set_optionC(solver); CHKERR(ierr);
            ierr = lis_matrix_create(#{@comm}, &A); CHKERR(ierr);
            ierr = lis_matrix_set_size(A, #{decomposer_code.indexCount}(), 0); CHKERR(ierr);
            ierr = lis_vector_create(#{@comm}, &x); CHKERR(ierr);
            ierr = lis_vector_set_size(x, #{decomposer_code.indexCount}(), 0); CHKERR(ierr);
            ierr = lis_vector_duplicate(x, &b); CHKERR(ierr);
            #ifndef NDEBUG
            {
              LIS_INT is, ie;
              ierr = lis_vector_get_range(b, &is, &ie); CHKERR(ierr);
              FINITA_ASSERT(first == is && last == ie-1);
              ierr = lis_vector_get_range(x, &is, &ie); CHKERR(ierr);
              FINITA_ASSERT(first == is && last == ie-1);
            }
            #endif
            ierr = lis_matrix_malloc(A, 0, nnz); CHKERR(ierr);
            #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
            while(#{SparsityPatternCode.itHasNext}(&it)) {
              #{NodeCoordCode.type} coord;
              coord = #{SparsityPatternCode.itNext}(&it);
              ierr = lis_matrix_set_value(LIS_INS_VALUE, #{mapper_code.index}(coord.row), #{mapper_code.index}(coord.column), #{jacobian_code.evaluate}(coord.row, coord.column), A); CHKERR(ierr);
            }
            ierr = lis_matrix_assemble(A); CHKERR(ierr);
            for(index = first; index <= last; ++index) {
              ierr = lis_vector_set_value(LIS_INS_VALUE, index, -#{residual_code.evaluate}(#{mapper_code.node}(index)), b); CHKERR(ierr);
            }
            ierr = lis_solve(A, b, x, solver); CHKERR(ierr);
      $
      stream << %$
        for(index = first; index <= last; ++index) {
          LIS_SCALAR dvalue;
          #{system_code.cresult} value;
          value = #{mapper_code.indexGet}(index);
          ierr = lis_vector_get_value(x, index, &dvalue); CHKERR(ierr);
          base += #{abs}(value);
          delta += #{abs}(dvalue);
          #{mapper_code.indexSet}(index, value + dvalue);
        }
        #{decomposer_code.synchronizeUnknowns}();
        ierr = lis_solver_destroy(solver); CHKERR(ierr);
        ierr = lis_matrix_destroy(A); CHKERR(ierr);
        ierr = lis_vector_destroy(x); CHKERR(ierr);
        ierr = lis_vector_destroy(b); CHKERR(ierr);
      $
      if mpi?
        stream << %${
          double base_, delta_; /* TODO : complex??? */
          ierr = MPI_Reduce(&base, &base_, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          ierr = MPI_Reduce(&delta, &delta_, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          norm = !step || FinitaFloatsAlmostEqual(base_, 0) ? 1 : delta_ / base_;
        }$
      else
        stream << %$
          norm = !step || FinitaFloatsAlmostEqual(base, 0) ? 1 : delta / base;
        $
      end
      stream << %$
        stop = norm < #{@solver.rtol};
        #ifndef NDEBUG
          FINITA_HEAD {
            printf("norm=%e\\n", norm);
            fflush(stdout);
          }
        #endif
      $
      if mpi?
        stream << %$
          ierr = MPI_Bcast(&stop, 1, MPI_INT, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
        $
      end
      stream << %$
          ++step;
        } while(!stop);
        #{free}(nnz);
        FINITA_LEAVE;
      }$
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
    def write_finalizer(stream)
      stream << %$#{cleanup}();$
    end
  end # Code
end # MUMPS


end # Finita
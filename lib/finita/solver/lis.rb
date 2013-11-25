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
    end
    def entities
      @entities.nil? ? @entities = super + [@numeric_array_code].compact : @entities
    end
    def write_setup_body(stream)
      super
      comm = mpi? ? :MPI_COMM_WORLD : 0
      stream << %${
        LIS_INT ierr;
        ierr = lis_solver_create(&#{solver}); CHKERR(ierr);
        ierr = lis_solver_set_optionC(#{solver}); CHKERR(ierr);
        ierr = lis_matrix_create(#{comm}, &#{a}); CHKERR(ierr);
        ierr = lis_matrix_set_size(#{a}, #{decomposer_code.indexCount}(), 0); CHKERR(ierr);
        ierr = lis_matrix_set_type(#{a}, LIS_MATRIX_CSR); CHKERR(ierr);
        ierr = lis_vector_create(#{comm}, &#{x}); CHKERR(ierr);
        ierr = lis_vector_set_size(#{x}, #{decomposer_code.indexCount}(), 0); CHKERR(ierr);
        ierr = lis_vector_duplicate(#{x}, &#{b}); CHKERR(ierr);
      }$
      stream << %$#{@numeric_array_code.ctor}(&#{array}, #{mapper_code.size}());$ if @have_array
    end
    def write_cleanup_body(stream)
      super
      stream << %${
        LIS_INT ierr;
        ierr = lis_solver_destroy(#{solver}); CHKERR(ierr);
        ierr = lis_matrix_destroy(#{a}); CHKERR(ierr);
        ierr = lis_vector_destroy(#{x}); CHKERR(ierr);
        ierr = lis_vector_destroy(#{b}); CHKERR(ierr);
      }$
      stream << %$#{@numeric_array_code.dtor}(&#{array});$ if @have_array
    end
    def write_defs(stream)
      stream << %$
        static LIS_MATRIX #{a};
        static LIS_VECTOR #{b}, #{x};
        static LIS_SOLVER #{solver};
      $
      stream << %$static #{@numeric_array_code.type} #{array};$ if @have_array
      super
      @solver.linear? ? write_solve_linear(stream) : write_solve_nonlinear(stream)
    end
    def write_solve_linear(stream)
      stream << %$
        void #{system_code.solve}(void) {
          LIS_INT ierr, first, last, index;
          #{SparsityPatternCode.it} it;
          FINITA_ENTER;
          first = #{decomposer_code.firstIndex}();
          last = #{decomposer_code.lastIndex}();
          #ifndef NDEBUG
          {
            LIS_INT is, ie;
            ierr = lis_vector_get_range(#{b}, &is, &ie); CHKERR(ierr);
            FINITA_ASSERT(first == is && last == ie-1);
            ierr = lis_vector_get_range(#{x}, &is, &ie); CHKERR(ierr);
            FINITA_ASSERT(first == is && last == ie-1);
          }
          #endif
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          while(#{SparsityPatternCode.itHasNext}(&it)) {
            #{NodeCoordCode.type} coord;
            coord = #{SparsityPatternCode.itNext}(&it);
            ierr = lis_matrix_set_value(LIS_INS_VALUE, #{mapper_code.index}(coord.row), #{mapper_code.index}(coord.column), #{lhs_code.evaluate}(coord.row, coord.column), #{a}); CHKERR(ierr);
          }
          for(index = first; index <= last; ++index) {
            ierr = lis_vector_set_value(LIS_INS_VALUE, index, -#{rhs_code.evaluate}(#{mapper_code.node}(index)), #{b}); CHKERR(ierr);
          }
          ierr = lis_solve(#{a}, #{b}, #{x}, #{solver}); CHKERR(ierr);
          for(index = first; index <= last; ++index) {
            LIS_SCALAR value;
            ierr = lis_vector_get_value(#{x}, index, &value); CHKERR(ierr);
            #{mapper_code.indexSet}(index, value);
          }
          #{decomposer_code.synchronizeUnknowns}();
          FINITA_LEAVE;
        }
      $
    end
    def write_solve_nonlinear(stream)
      abs = CAbs[system_code.result]
      stream << %$
        void #{system_code.solve}(void) {
          int stop, step = 0;
          LIS_INT ierr, first, last, index;
          size_t size;
          #{SparsityPatternCode.it} it;
          FINITA_ENTER;
          size = #{mapper_code.size}();
          first = #{decomposer_code.firstIndex}();
          last = #{decomposer_code.lastIndex}();
          #ifndef NDEBUG
          {
            LIS_INT is, ie;
            ierr = lis_vector_get_range(#{b}, &is, &ie); CHKERR(ierr);
            FINITA_ASSERT(first == is && last == ie-1);
            ierr = lis_vector_get_range(#{x}, &is, &ie); CHKERR(ierr);
            FINITA_ASSERT(first == is && last == ie-1);
          }
          #endif
          do {
            double norm, base = 0, delta = 0; /* TODO : complex */
            #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
            while(#{SparsityPatternCode.itHasNext}(&it)) {
              #{NodeCoordCode.type} coord;
              coord = #{SparsityPatternCode.itNext}(&it);
              ierr = lis_matrix_set_value(LIS_INS_VALUE, #{mapper_code.index}(coord.row), #{mapper_code.index}(coord.column), #{jacobian_code.evaluate}(coord.row, coord.column), #{a}); CHKERR(ierr);
            }
            for(index = first; index <= last; ++index) {
              ierr = lis_vector_set_value(LIS_INS_VALUE, index, -#{residual_code.evaluate}(#{mapper_code.node}(index)), #{b}); CHKERR(ierr);
            }
            ierr = lis_solve(#{a}, #{b}, #{x}, #{solver}); CHKERR(ierr);
      $
      stream << %$
        for(index = first; index <= last; ++index) {
          LIS_SCALAR dx;
          #{system_code.cresult} x;
          x = #{mapper_code.indexGet}(index);
          ierr = lis_vector_get_value(#{x}, index, &dx); CHKERR(ierr);
          base += #{abs}(x);
          delta += #{abs}(dx);
          #{mapper_code.indexSet}(index, x + dx);
        }
        #{decomposer_code.synchronizeUnknowns}();
      $
      if mpi?
        stream << %$
          ierr = MPI_Reduce(&base, &base, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          ierr = MPI_Reduce(&delta, &delta, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
        $
      end
      stream << %$
        norm = !step || base == 0 ? 1 : delta/base;
        stop = norm < #{@solver.rtol};
        #ifndef NDEBUG
          FINITA_HEAD {
            printf("norm=%d\\n", norm);
            fflush(stdout);
          }
        #endif
      $
      if mpi?
        stream << %$
          ierr = MPI_Bcast(&stop, &stop, MPI_INT, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
        $
      end
      stream << %$
          ++step;
        } while(!stop);
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
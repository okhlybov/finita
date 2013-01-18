module Finita


class Solver::MUMPS < Solver::Matrix
  class Code < Solver::Matrix::Code
    @@mumps = {Float=>:dmumps, Complex=>:zmumps}
    def initialize(*args)
      super
      @mumps = @@mumps[@system_code.system_type]
      @mumps_c = "#{@mumps}_c".to_sym
      @MUMPS = @mumps.to_s.upcase.to_sym
    end
    def write_defs(stream)
      super
      case @mumps
        when :dmumps
          stream << %$
            #include "dmumps_c.h"
          $
        when :zmumps
          stream << %$
            #include "zmumps_c.h"
          $
      end
      matrix_code = @solver.linear? ? @lhs_code : @jacobian_code
      vector_code = @solver.linear? ? @rhs_code : @residual_code
      stream << %$
        #define ICNTL(x) icntl[(x)-1]
        #define INFO(x) info[(x)-1]
        #define INFOG(x) infog[(x)-1]
        static #{@MUMPS}_STRUC_C #{ctx};
        static void #{invoke}() {
          #{@mumps_c}(&#{ctx});
          FINITA_HEAD if(#{ctx}.INFOG(1) < 0) {
            char msg[1024];
            snprintf(msg, 1024, "MUMPS returned error code %d", #{ctx}.INFOG(1)); /* FIXME snprintf */
            FINITA_FAILURE(msg);
          }
        }
        int #{setup}(void) {
          size_t index;
          #{ctx}.job = -1; /* setup phase */
          #{ctx}.par = 1; /* computing host */
          #{ctx}.sym = 0; /* unsymmetric matrix mode */
          #{ctx}.comm_fortran = -987654; /* MPI_COMM_WORLD */
          #{invoke}();
          #{ctx}.job = 1; /* analysis phase */
          #{ctx}.ICNTL(3) = -1; /* disable debugging output */
          #{ctx}.ICNTL(5) = 0; /* assembled matrix format */
          #{ctx}.ICNTL(6) = 1; /* permutation that does not require the values of the matrix to be specified */
          /*#{ctx}.ICNTL(7) = 1;*/ /* AMD ordering */
          #{ctx}.ICNTL(18) = 3; /* distributed matrix format */
          #{ctx}.ICNTL(20) = 0; /* centralized vector format */
          #{ctx}.ICNTL(21) = 0; /* centralized solution format */
          #{ctx}.n = #{@mapper_code.size}();
          #{ctx}.nz_loc = #{matrix_code.size}();
          #{ctx}.irn_loc = (int*) #{malloc}(#{ctx}.nz_loc*sizeof(int)); #{assert}(#{ctx}.irn_loc);
          #{ctx}.jcn_loc = (int*) #{malloc}(#{ctx}.nz_loc*sizeof(int)); #{assert}(#{ctx}.jcn_loc);
          #{ctx}.a_loc = (#{@system_code.result}*) #{malloc}(#{ctx}.nz_loc*sizeof(#{@system_code.result})); #{assert}(#{ctx}.a_loc);
          FINITA_HEAD {
            #{ctx}.rhs = (#{@system_code.result}*) #{malloc}(#{ctx}.n*sizeof(#{@system_code.result})); #{assert}(#{ctx}.rhs);
          }
          #{ctx}.nrhs = 1;
          for(index = 0; index < #{ctx}.nz_loc; ++index) {
            #{@coord.type} coord = #{matrix_code.coord}(index);
            #{ctx}.irn_loc[index] = #{@mapper_code.getIndex}(coord.row) + 1;
            #{ctx}.jcn_loc[index] = #{@mapper_code.getIndex}(coord.column) + 1;
          }
          #{invoke}();
      $
      stream << '}'
      stream << %$
        int #{@system_code.solve}(void) {
          size_t index;
          #{ctx}.job = 5; /* factorization & solve phase */
          for(index = 0; index < #{ctx}.nz_loc; ++index) {
            #{ctx}.a_loc[index] = #{matrix_code.value}(index);
          }
          FINITA_HEAD {
            for(index = 0; index < #{ctx}.n; ++index) {
              #{ctx}.rhs[index] = #{vector_code.value}(index);
            }
          }
          #{invoke}();
          return 0;
        }
      $
      stream << %$
        #undef ICNTL
        #undef INFO
        #undef INFOG
      $
    end
  end # Code
end # MUMPS


end # Finita
module Finita


class Solver::MUMPS < Solver::Matrix
  class Code < Solver::Matrix::Code
    @@mumps = {Float=>:dmumps, Complex=>:zmumps}
    def initialize(*args)
      super
      system_code.initializer_codes << self
      @mumps = @@mumps[system_code.result]
      @mumps_c = "#{@mumps}_c".to_sym
      @MUMPS = @mumps.to_s.upcase.to_sym
    end
    def write_setup_body(stream)
      super
      stream << %${
        size_t index = 0;
        #{SparsityPatternCode.it} it;
        #{ctx}.par = 1; /* computing host */
        #{ctx}.sym = 0; /* unsymmetric matrix mode */
        #{ctx}.comm_fortran = -987654; /* MPI_COMM_WORLD */
        #{invoke}(-1);
        #{ctx}.ICNTL(3) = -1; /* disable debugging output */
        #{ctx}.ICNTL(5) = 0; /* assembled matrix format */
        #{ctx}.ICNTL(6) = 1; /* permutation that does not require the values of the matrix to be specified */
        /*#{ctx}.ICNTL(7) = 1;*/ /* AMD ordering */
        #{ctx}.ICNTL(18) = 3; /* distributed matrix format */
        #{ctx}.ICNTL(20) = 0; /* centralized vector format */
        #{ctx}.ICNTL(21) = 0; /* centralized solution format */
        #{ctx}.n = #{mapper_code.size}();
        #{ctx}.nz_loc = #{SparsityPatternCode.size}(&#{sparsity});
        #{ctx}.irn_loc = (int*) #{malloc}(#{ctx}.nz_loc*sizeof(int)); #{assert}(#{ctx}.irn_loc);
        #{ctx}.jcn_loc = (int*) #{malloc}(#{ctx}.nz_loc*sizeof(int)); #{assert}(#{ctx}.jcn_loc);
        #{ctx}.a_loc = (#{system_code.cresult}*) #{calloc}(#{ctx}.nz_loc, sizeof(#{system_code.cresult})); #{assert}(#{ctx}.a_loc);
        #{ctx}.rhs = (#{system_code.cresult}*) #{calloc}(#{ctx}.n, sizeof(#{system_code.cresult})); #{assert}(#{ctx}.rhs);
        #{ctx}.nrhs = 1;
        #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
        while(#{SparsityPatternCode.itHasNext}(&it)) {
          #{NodeCoordCode.type} coord = #{SparsityPatternCode.itNext}(&it);
          #{ctx}.irn_loc[index] = #{mapper_code.index}(coord.row) + 1;
          #{ctx}.jcn_loc[index] = #{mapper_code.index}(coord.column) + 1;
          ++index;
        }
        #{invoke}(1);
      }$
    end
    def write_defs(stream)
      stream << %$
        #include <#{@mumps_c}.h>
        #define ICNTL(x) icntl[(x)-1]
        #define INFO(x) info[(x)-1]
        #define INFOG(x) infog[(x)-1]
        static #{@MUMPS}_STRUC_C #{ctx};
        static void #{invoke}(int job) {
          #{ctx}.job = job;
          #{@mumps_c}(&#{ctx});
          FINITA_HEAD if(#{ctx}.INFOG(1) < 0) {
            char msg[1024];
            snprintf(msg, 1024, "MUMPS returned error code %d", #{ctx}.INFOG(1)); /* FIXME snprintf */
            FINITA_FAILURE(msg);
          }
        }
      $
      super
      abs = CAbs[system_code.result]
      if @solver.linear?
        stream << %$
          void #{system_code.solve}(void) {
            size_t index;
            for(index = 0; index < #{ctx}.nz_loc; ++index) {
              #{NodeCode.type} row = #{mapper_code.node}(#{ctx}.irn_loc[index] - 1), column = #{mapper_code.node}(#{ctx}.jcn_loc[index] - 1);
              #{ctx}.a_loc[index] = #{lhs_code.evaluate}(row, column);
            }
            for(index = 0; index < #{ctx}.n; ++index) {
              #{ctx}.rhs[index] = #{rhs_code.evaluate}(#{mapper_code.node}(index));
            }
            #{invoke}(5);
            for(index = 0; index < #{ctx}.n; ++index) {
              #{mapper_code.indexSet}(index, #{ctx}.rhs[index]);
            }
          }
        $
      else
        stream << %$
          void #{system_code.solve}(void) {
            #{system_code.cresult} norm;
            size_t index;
            int first = 1;
            do {
              #{system_code.cresult} base = 0, delta = 0;
              for(index = 0; index < #{ctx}.nz_loc; ++index) {
                #{NodeCode.type} row = #{mapper_code.node}(#{ctx}.irn_loc[index] - 1), column = #{mapper_code.node}(#{ctx}.jcn_loc[index] - 1);
                #{ctx}.a_loc[index] = #{jacobian_code.evaluate}(row, column);
                //printf("a_loc[%d] = %e\\n", index, #{ctx}.a_loc[index]);
              }
              for(index = 0; index < #{ctx}.n; ++index) {
                #{ctx}.rhs[index] = -#{residual_code.evaluate}(#{mapper_code.node}(index));
                //printf("rhs[%d] = %e\\n", index, #{ctx}.rhs[index]);
              }
              #{invoke}(5);
              for(index = 0; index < #{ctx}.n; ++index) {
                #{system_code.cresult} value = #{mapper_code.indexGet}(index);
                //printf("value[%d] = %e\\n", index, value);
                base += #{abs}(value);
                //printf("delta[%d] = %e\\n", index, #{ctx}.rhs[index]);
                delta += #{abs}(#{ctx}.rhs[index]);
                #{mapper_code.indexSet}(index, value + #{ctx}.rhs[index]);
              }
              norm = first || base == 0 ? 1 : delta/base;
              //printf("norm = %e, delta=%e, base=%e\\n", norm, delta, base);
              first = 0;
            } while(norm > #{@solver.rtol});
          }
        $
      end
      stream << %$
        #undef ICNTL
        #undef INFO
        #undef INFOG
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # MUMPS


end # Finita
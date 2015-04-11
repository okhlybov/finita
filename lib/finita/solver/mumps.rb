module Finita


class Solver::MUMPS < Solver::Matrix
  def initialize(*args)
    super
    raise "unsupported environment" unless environment.seq? or environment.mpi?
  end
  class Code < Solver::Matrix::Code
    @@mumps = {Float=>:dmumps, Complex=>:zmumps}
    def initialize(*args)
      super
      system_code.initializer_codes << self
      system_code.finalizer_codes << self
      @mumps = @@mumps[system_code.result]
      @mumps_c = "#{@mumps}_c".to_sym
      @MUMPS = @mumps.to_s.upcase.to_sym
      @numeric_array_code = NumericArrayCode[system_code.result] if mpi?
    end
    def entities
      super.concat([@numeric_array_code].compact)
    end
    def write_setup_body(stream)
      super
      stream << %${
        int index = 0;
        #{SparsityPatternCode.it} it;
        FINITA_ENTER;
        #{ctx}.par = 1; /* computing host */
        #{ctx}.sym = 0; /* unsymmetric matrix mode */
        #{ctx}.comm_fortran = -987654; /* MPI_COMM_WORLD */
        #{invoke}(-1);
        #ifdef NDEBUG
          #{ctx}.ICNTL(4) = 1; /* print errors only */
        #else
          #{ctx}.ICNTL(4) = 2; /* terse debugging output */
        #endif
        #{ctx}.ICNTL(5) = 0; /* assembled matrix format */
        #{ctx}.ICNTL(6) = 1; /* permutation that does not require the values of the matrix to be specified */
        #{ctx}.ICNTL(18) = 3; /* distributed matrix format */
        #{ctx}.ICNTL(20) = 0; /* centralized vector format */
        #{ctx}.ICNTL(21) = 0; /* centralized solution format */
        #{ctx}.ICNTL(24) = 1; /* null pivot workaround */
        #{ctx}.n = #{mapper_code.size}();
        #{ctx}.nz_loc = #{SparsityPatternCode.size}(&#{sparsity});
        #{ctx}.irn_loc = (int*) #{malloc}(#{ctx}.nz_loc*sizeof(int)); #{assert}(#{ctx}.irn_loc);
        #{ctx}.jcn_loc = (int*) #{malloc}(#{ctx}.nz_loc*sizeof(int)); #{assert}(#{ctx}.jcn_loc);
        #{ctx}.a_loc = (#{system_code.cresult}*) #{calloc}(#{ctx}.nz_loc, sizeof(#{system_code.cresult})); #{assert}(#{ctx}.a_loc);
        FINITA_HEAD {
          #{ctx}.rhs = (#{system_code.cresult}*) #{calloc}(#{ctx}.n, sizeof(#{system_code.cresult})); #{assert}(#{ctx}.rhs);
        }
        #{ctx}.nrhs = 1;
        #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
        while(#{SparsityPatternCode.itMove}(&it)) {
          #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
          #{ctx}.irn_loc[index] = #{mapper_code.index}(coord.row) + 1;
          #{ctx}.jcn_loc[index] = #{mapper_code.index}(coord.column) + 1;
          ++index;
        }
        #{invoke}(1);
      $
      stream << "#{@numeric_array_code.ctor}(&#{array}, #{ctx}.n);" if mpi?
      stream << "FINITA_LEAVE;}"
    end
    def write_cleanup_body(stream)
      super
      stream << %${
        FINITA_ENTER;
        #{free}(#{ctx}.irn_loc);
        #{free}(#{ctx}.jcn_loc);
        FINITA_HEAD {
          #{free}(#{ctx}.rhs);
        }
        #{invoke}(-2);
      $
      stream << "#{@numeric_array_code.dtor}(&#{array});" if mpi?
      stream << "FINITA_LEAVE;}"
    end
    def write_defs(stream)
      stream << %$static #{@numeric_array_code.type} #{array};$ if mpi?
      stream << %$
        #include <#{@mumps_c}.h>
        #define ICNTL(x) icntl[(x)-1]
        #define INFO(x) info[(x)-1]
        #define INFOG(x) infog[(x)-1]
        static #{@MUMPS}_STRUC_C #{ctx};
        static void #{invoke}(int job) {
          FINITA_ENTER;
          #{ctx}.job = job;
          #{@mumps_c}(&#{ctx});
          FINITA_HEAD if(#{ctx}.INFOG(1) < 0) {
            char msg[1024];
            snprintf(msg, 1024, "MUMPS returned error code %d", #{ctx}.INFOG(1)); /* FIXME snprintf */
            FINITA_FAILURE(msg);
          }
          FINITA_LEAVE;
        }
      $
      super
      abs = CAbs[system_code.result]
      if @solver.linear?
        stream << %$
          void #{system_code.solve}(void) {
            int index;
            FINITA_ENTER;
            for(index = 0; index < #{ctx}.nz_loc; ++index) {
              #{ctx}.a_loc[index] = #{lhs_code.evaluate}(#{mapper_code.node}(#{ctx}.irn_loc[index] - 1), #{mapper_code.node}(#{ctx}.jcn_loc[index] - 1));
            }
        $
        if mpi?
          stream << %${
            int first = #{decomposer_code.firstIndex}(), last = #{decomposer_code.lastIndex}();
            for(index = first; index <= last; ++index) {
              #{@numeric_array_code.set}(&#{array}, index, -#{rhs_code.evaluate}(#{mapper_code.node}(index)));
            }
            #{decomposer_code.gatherArray}(&#{array});
            FINITA_HEAD for(index = 0; index < #{ctx}.n; ++index) {
              #{ctx}.rhs[index] = #{@numeric_array_code.get}(&#{array}, index);
            }
          $
        else
          stream << %$
            for(index = 0; index < #{ctx}.n; ++index) {
              #{ctx}.rhs[index] = -#{rhs_code.evaluate}(#{mapper_code.node}(index));
            }
          $
        end
        stream << %$#{invoke}(5);$
        if mpi?
          stream << %$
            FINITA_HEAD for(index = 0; index < #{ctx}.n; ++index) {
              #{@numeric_array_code.set}(&#{array}, index, #{ctx}.rhs[index]);
            }
            #{decomposer_code.broadcastArray}(&#{array});
            for(index = 0; index < #{ctx}.n; ++index) {
              #{mapper_code.indexSet}(index, #{@numeric_array_code.get}(&#{array}, index));
            }
          }$
        else
          stream << %$
            for(index = 0; index < #{ctx}.n; ++index) {
              #{mapper_code.indexSet}(index, #{ctx}.rhs[index]);
            }
          $
        end
        stream << "FINITA_LEAVE;}"
      else
        stream << %$
          void #{system_code.solve}(void) {
            #{system_code.cresult} norm;
            int index, step = 0;
            int stop, first = 1;
            FINITA_ENTER;
            do {
              #{system_code.cresult} base = 0, delta = 0;
              for(index = 0; index < #{ctx}.nz_loc; ++index) {
                #{ctx}.a_loc[index] = #{jacobian_code.evaluate}(#{mapper_code.node}(#{ctx}.irn_loc[index] - 1), #{mapper_code.node}(#{ctx}.jcn_loc[index] - 1));
              }
        $
        if mpi?
          stream << %${
            int ierr;
            int first = #{decomposer_code.firstIndex}(), last = #{decomposer_code.lastIndex}();
            for(index = first; index <= last; ++index) {
              #{@numeric_array_code.set}(&#{array}, index, #{residual_code.evaluate}(#{mapper_code.node}(index)));
            }
            #{decomposer_code.gatherArray}(&#{array});
            FINITA_HEAD for(index = 0; index < #{ctx}.n; ++index) {
              #{ctx}.rhs[index] = -#{@numeric_array_code.get}(&#{array}, index);
            }
          $
        else
          stream << %$
            for(index = 0; index < #{ctx}.n; ++index) {
              #{ctx}.rhs[index] = -#{residual_code.evaluate}(#{mapper_code.node}(index));
            }
          $
        end
        stream << %$#{invoke}(5);$
        if mpi?
          stream << %$
            FINITA_HEAD for(index = 0; index < #{ctx}.n; ++index) {
              #{@numeric_array_code.set}(&#{array}, index, #{ctx}.rhs[index]);
            }
            #{decomposer_code.broadcastArray}(&#{array});
            for(index = 0; index < #{ctx}.n; ++index) {
              #{system_code.cresult} dvalue = #{@numeric_array_code.get}(&#{array}, index), value = #{mapper_code.indexGet}(index);
              FINITA_HEAD {
                base += #{abs}(value);
                delta += #{abs}(dvalue);
              }
              #{mapper_code.indexSet}(index, value + dvalue);
            }
            FINITA_HEAD {
              norm = first || FinitaFloatsAlmostEqual(base, 0) ? 1 : delta / base;
              first = 0;
              stop = norm < #{@solver.rtol}; /* FIXME : wont work for complex numbers */
            }
            ierr = MPI_Bcast(&stop, 1, MPI_INT, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          }$
        else
          stream << %$
            for(index = 0; index < #{ctx}.n; ++index) {
              #{system_code.cresult} value = #{mapper_code.indexGet}(index);
              base += #{abs}(value);
              delta += #{abs}(#{ctx}.rhs[index]);
              #{mapper_code.indexSet}(index, value + #{ctx}.rhs[index]);
            }
            norm = first || FinitaFloatsAlmostEqual(base, 0) ? 1 : delta / base;
            first = 0;
            stop = norm < #{@solver.rtol};
          $
        end
        stream << %$
            ++step;} while(!stop);
            FINITA_LEAVE;
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
    def write_finalizer(stream)
      stream << %$#{cleanup}();$
    end
  end # Code
end # MUMPS


end # Finita
module Finita


class Solver::ViennaCL < Solver::Matrix
  StaticCode = Class.new(Finita::Code) do
    def write_defs(stream)
      super
      stream << %$
        #ifndef __cplusplus
          #error ViennaCL solver requires this source to be compiled by C++ compiler
        #endif
        #include <viennacl/compressed_matrix.hpp>
        #include <viennacl/linalg/gmres.hpp>
        #include <viennacl/linalg/ilu.hpp>
        #include <viennacl/vector.hpp>
        #include <vector>
        #include <map>
        using namespace viennacl;
        using namespace viennacl::linalg;
      $
    end
  end.new(:FinitaViennaCL) # StaticCode
  class Code < Solver::Matrix::Code
    def initialize(*args)
      super
      system_code.initializer_codes << self
      system_code.finalizer_codes << self
    end
    def entities; super << StaticCode end
    def write_defs(stream)
      super
      @solver.linear? ? write_solve_linear(stream) : write_solve_nonlinear(stream)
    end
    # def write_solve_linear(stream)
    def write_solve_nonlinear(stream)
      abs = CAbs[system_code.result]
      stream << %$
        void #{system_code.solve}(void) {
          int stop, step = 0;
          size_t index;
          #{SparsityPatternCode.it} it;
          FINITA_ENTER;
          const size_t neq = #{mapper_code.size}(), nnz = #{SparsityPatternCode.size}(&#{sparsity});
          std::vector< std::map<size_t, #{system_code.cresult}> > m(neq);
          compressed_matrix<#{system_code.cresult}> A(neq, neq);
          A.reserve(nnz);
          std::vector<#{system_code.cresult}> v(neq);
          vector<#{system_code.cresult}> B(neq);
          do {
            double norm, base = 0, delta = 0; /* TODO : complex */
            #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
            while(#{SparsityPatternCode.itMove}(&it)) {
              #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
              m[#{mapper_code.index}(coord.row)][#{mapper_code.index}(coord.column)] = #{jacobian_code.evaluate}(coord.row, coord.column);
            }
            copy(m, A);
            for(index = 0; index < neq; ++index) {
              v[index] = -#{residual_code.evaluate}(#{mapper_code.node}(index));
            }
            copy(v, B);
            vector<#{system_code.cresult}> X = solve(A, B, gmres_tag(), block_ilu_precond<compressed_matrix<#{system_code.cresult}>, ilu0_tag>(A, ilu0_tag()));
            copy(X, v);
            for(index = 0; index < neq; ++index) {
              const #{system_code.cresult} value = #{mapper_code.indexGet}(index), dvalue = v[index];
              base += #{abs}(value);
              delta += #{abs}(dvalue);
              #{mapper_code.indexSet}(index, value + dvalue);
            }
            norm = !step || FinitaFloatsAlmostEqual(base, 0) ? 1 : delta / base;
            stop = norm < #{@solver.rtol};
            #ifndef NDEBUG
              FINITA_HEAD {
                printf("norm=%e\\n", norm);
                fflush(stdout);
              }
            #endif
            ++step;
          } while(!stop);
          FINITA_LEAVE;
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
    def write_finalizer(stream)
      stream << %$#{cleanup}();$
    end
  end # Code
end # ViennaCL


end # Finita
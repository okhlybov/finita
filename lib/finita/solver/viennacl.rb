module Finita


class Solver::ViennaCL < Solver::Matrix
  StaticCode = Class.new(Finita::Code) do
    def write_decls(stream)
      super
      stream << %$
        #ifndef __cplusplus
          #error ViennaCL backend requires this source to be compiled by C++ compiler
        #endif
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
      # push/pop macro pragmas are supported by at least MSVC and GCC compilers
      Finita::Field.defined_fields.each do |field|
        stream << %$
          #pragma push_macro("#{field}")
          #undef #{field}
        $
      end
      stream << %$
        #include "viennacl/compressed_matrix.hpp"
        #include "viennacl/linalg/gmres.hpp"
        #include "viennacl/linalg/ilu.hpp"
        #include "viennacl/vector.hpp"
        #include <vector>
        #include <map>
        using namespace viennacl;
        using namespace viennacl::linalg;
      $
      @solver.linear? ? write_solve_linear(stream) : write_solve_nonlinear(stream)
      Finita::Field.defined_fields.each do |field|
        stream << %$
          #pragma pop_macro("#{field}")
        $
      end
    end
    def write_solve_linear(stream)
      stream << %$
        int #{system_code.solve}(void) {
          size_t index;
          #{SparsityPatternCode.it} it;
          FINITA_ENTER;
          const size_t neq = #{mapper_code.size}(), nnz = #{SparsityPatternCode.size}(&#{sparsity});
          std::vector< std::map<unsigned int, #{system_code.cresult}> > m(neq);
          compressed_matrix<#{system_code.cresult}> A(neq, neq);
          A.reserve(nnz);
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          while(#{SparsityPatternCode.itMove}(&it)) {
            #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
            m[#{mapper_code.index}(coord.row)][#{mapper_code.index}(coord.column)] = #{lhs_code.evaluate}(coord.row, coord.column);
          }
          copy(m, A);
          std::vector<#{system_code.cresult}> v(neq);
          vector<#{system_code.cresult}> B(neq);
          for(index = 0; index < neq; ++index) {
            v[index] = -#{rhs_code.evaluate}(#{mapper_code.node}(index));
          }
          copy(v, B);
          vector<#{system_code.cresult}> X = solve(A, B, gmres_tag(#{@solver.relative_tolerance}, #{@solver.max_steps}), block_ilu_precond<compressed_matrix<#{system_code.cresult}>, ilu0_tag>(A, ilu0_tag()));
          copy(X, v);
          for(index = 0; index < neq; ++index) {
            #{mapper_code.indexSet}(index, v[index]);
          }
          #{decomposer_code.synchronizeUnknowns}();
          FINITA_RETURN(1); /* FIXME */
        }
      $
    end
    def write_solve_nonlinear(stream)
      abs = CAbs[system_code.result]
      stream << %$
        int #{system_code.solve}(void) {
          int stop, step = 0;
          size_t index;
          #{SparsityPatternCode.it} it;
          FINITA_ENTER;
          const size_t neq = #{mapper_code.size}(), nnz = #{SparsityPatternCode.size}(&#{sparsity});
          std::vector< std::map<unsigned int, #{system_code.cresult}> > m(neq);
          viennacl::compressed_matrix<#{system_code.cresult}> A(neq, neq);
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
            vector<#{system_code.cresult}> X = solve(A, B, gmres_tag(#{@solver.relative_tolerance}, #{@solver.max_steps}), block_ilu_precond<compressed_matrix<#{system_code.cresult}>, ilu0_tag>(A, ilu0_tag()));
            copy(X, v);
            for(index = 0; index < neq; ++index) {
              const #{system_code.cresult} value = #{mapper_code.indexGet}(index), dvalue = v[index];
              base += #{abs}(value);
              delta += #{abs}(dvalue);
              #{mapper_code.indexSet}(index, value + dvalue);
            }
            #{decomposer_code.synchronizeUnknowns}();
            norm = !step || FinitaFloatsAlmostEqual(base, 0) ? 1 : delta / base;
            stop = norm < #{@solver.relative_tolerance};
            #ifndef NDEBUG
              FINITA_HEAD {
                printf("norm=%e\\n", norm);
                fflush(stdout);
              }
            #endif
            ++step;
          } while(!stop);
          FINITA_RETURN(1); /* FIXME */
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
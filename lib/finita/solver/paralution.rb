module Finita


class Solver::Paralution < Solver::Matrix
  StaticCode = Class.new(Finita::Code) do
    def write_decls(stream)
      super
      stream << %$
        #ifndef __cplusplus
          #error Paralution backend requires this source to be compiled by C++ compiler
        #endif
        #include "paralution.hpp"
        using namespace paralution;
      $
    end
    def write_initializer(stream)
      stream << %$
        init_paralution();
        #ifndef NDEBUG
          info_paralution();
        #endif
      $
    end
    def write_finalizer(stream)
      stream << %$stop_paralution();$
    end
  end.new(:FinitaParalution) # StaticCode
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
    def write_decls(stream)
      super
      stream << %$
        static int* #{mcols};
        static int* #{mrows};
        static int* #{vrows};
        static #{system_code.cresult}* #{mvals};
        static #{system_code.cresult}* #{vvals};
        static #{system_code.cresult}* #{rvals};
        static LocalMatrix<#{system_code.cresult}> *#{matrix};
        static LocalVector<#{system_code.cresult}> *#{vector};
        static LocalVector<#{system_code.cresult}> *#{result};
        typedef CG<LocalMatrix<#{system_code.cresult}>,LocalVector<#{system_code.cresult}>,#{system_code.cresult}> #{solverType};
        typedef ILU<LocalMatrix<#{system_code.cresult}>,LocalVector<#{system_code.cresult}>,#{system_code.cresult}> #{pcType};
        static #{solverType} *#{solver};
        static #{pcType} *#{pc};
      $
    end
    def write_setup_body(stream)
      super
      stream << %${
        const int nnz = #{SparsityPatternCode.size}(&#{sparsity});
        #{mcols} = new int[nnz];
        #{mrows} = new int[nnz];
        #{mvals} = new #{system_code.cresult}[nnz];
        #{SparsityPatternCode.it} it;
        #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
        int index = 0;
        while(#{SparsityPatternCode.itMove}(&it)) {
          #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
          #{mcols}[index] = #{mapper_code.index}(coord.column);
          #{mrows}[index] = #{mapper_code.index}(coord.row);
          ++index;
        }
        #{matrix} = new LocalMatrix<#{system_code.cresult}>;
        #{matrix}->Assemble(#{mrows}, #{mcols}, #{mvals}, nnz, "A");
        #{matrix}->MoveToAccelerator();
        const int neq = #{mapper_code.size}();
        #{vrows} = new int[nnz];
        for(index = 0; index < neq; ++index) #{vrows}[index] = index;
        #{vvals} = new #{system_code.cresult}[neq];
        #{rvals} = new #{system_code.cresult}[neq];
        #{vector} = new LocalVector<#{system_code.cresult}>;
        #{vector}->Allocate("b", neq);
        #{vector}->MoveToAccelerator();
        #{result} = new LocalVector<#{system_code.cresult}>;
        #{solver} = new #{solverType};
        #{solver}->SetOperator(*#{matrix});
        #{pc} = new #{pcType};
        #{pc}->Set(1);
        #{solver}->SetPreconditioner(*#{pc});
        #{solver}->Build();
        #{solver}->MoveToHost();
      }$
    end
    def write_cleanup_body(stream)
      stream << %$
        delete #{solver};
        delete #{pc};
        delete #{matrix};
        delete #{vector};
        delete #{result};
        delete [] #{mcols};
        delete [] #{mrows};
        delete [] #{vrows};
        delete [] #{mvals};
        delete [] #{vvals};
        delete [] #{rvals};
      $
      super
    end
    def write_defs(stream)
      super
      @solver.linear? ? write_solve_linear(stream) : write_solve_nonlinear(stream)
    end
    def write_solve_linear(stream)
      stream << %$
        void #{system_code.solve}(void) {
          FINITA_ENTER;
          #{SparsityPatternCode.it} it;
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          int index = 0;
          while(#{SparsityPatternCode.itMove}(&it)) {
            #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
            #{mvals}[index++] = #{lhs_code.evaluate}(coord.row, coord.column);
          }
          #{matrix}->AssembleUpdate(#{mvals});
          const int neq = #{mapper_code.size}();
          for(index = 0; index < neq; ++index) {
            #{vvals}[index] = -#{rhs_code.evaluate}(#{mapper_code.node}(index));
          }
          #{vector}->Assemble(#{vrows}, #{vvals}, neq, "b");
          #{result}->SetDataPtr(&#{rvals}, "x", neq);
          #{result}->MoveToAccelerator();
          #{solver}->ResetOperator(*#{matrix});
          #{solver}->Solve(*#{vector}, #{result});
          #{result}->MoveToHost();
          #{result}->LeaveDataPtr(&#{rvals});
          for(index = 0; index < neq; ++index) {
            #{mapper_code.indexSet}(index, #{rvals}[index]);
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
          #{SparsityPatternCode.it} it;
          FINITA_ENTER;
          const int neq = #{mapper_code.size}();
          do {
            double norm, base = 0, delta = 0; /* TODO : complex */
            #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
            int index = 0;
            while(#{SparsityPatternCode.itMove}(&it)) {
              #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
              #{mvals}[index++] = #{jacobian_code.evaluate}(coord.row, coord.column);
            }
            #{matrix}->AssembleUpdate(#{mvals});
            for(index = 0; index < neq; ++index) {
              #{vvals}[index] = -#{residual_code.evaluate}(#{mapper_code.node}(index));
            }
            #{vector}->Assemble(#{vrows}, #{vvals}, neq, "b");
            #{result}->SetDataPtr(&#{rvals}, "x", neq);
            #{result}->MoveToAccelerator();
            #{solver}->ResetOperator(*#{matrix});
            #{solver}->Solve(*#{vector}, #{result});
            #{result}->MoveToHost();
            #{result}->LeaveDataPtr(&#{rvals});
            for(index = 0; index < neq; ++index) {
              const #{system_code.cresult} value = #{mapper_code.indexGet}(index), dvalue = #{rvals}[index];
              base += #{abs}(value);
              delta += #{abs}(dvalue);
              #{mapper_code.indexSet}(index, value + dvalue);
            }
            #{decomposer_code.synchronizeUnknowns}();
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
end # Paralution


end # Finita
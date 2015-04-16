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
        static #{system_code.cresult}* #{mvals};
        static #{system_code.cresult}* #{vvals};
        static LocalMatrix<#{system_code.cresult}> *#{matrix};
        static LocalVector<#{system_code.cresult}> *#{vector};
        static LocalVector<#{system_code.cresult}> *#{result};
        typedef CG<LocalMatrix<#{system_code.cresult}>,LocalVector<#{system_code.cresult}>,#{system_code.cresult}> #{solverType};
        typedef Jacobi<LocalMatrix<#{system_code.cresult}>,LocalVector<#{system_code.cresult}>,#{system_code.cresult}> #{pcType};
        static #{solverType} *#{solver};
        static #{pcType} *#{pc};
      $
    end
    def write_setup_body(stream)
      super
      stream << %${
        double tic = paralution_time();
        const int neq = #{mapper_code.size}(), nnz = #{SparsityPatternCode.size}(&#{sparsity});
        #{mcols} = new int[nnz];
        #{mrows} = new int[nnz];
        #{mvals} = new #{system_code.cresult}[nnz];
        #{SparsityPatternCode.it} it;
        // matrix
        int index = 0;
        #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
        while(#{SparsityPatternCode.itMove}(&it)) {
          #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
          #{mcols}[index] = #{mapper_code.index}(coord.column);
          #{mrows}[index] = #{mapper_code.index}(coord.row);
          #{mvals}[index] = 1; // Dummy values
          ++index;
        }
        #{matrix} = new LocalMatrix<#{system_code.cresult}>;
        #{matrix}->Assemble(#{mrows}, #{mcols}, #{mvals}, nnz, "A");
        #{matrix}->MoveToAccelerator();
        #ifndef NDEBUG
          #{matrix}->Check();
        #endif
        // vector
        #{vector} = new LocalVector<#{system_code.cresult}>;
        #{vector}->Allocate("b", neq);
        #{vector}->LeaveDataPtr(&#{vvals});
        for(index = 0; index < neq; ++index) #{vvals}[index] = 1; // Dummy values
        #{vector}->SetDataPtr(&#{vvals}, "b", neq);
        #{vector}->MoveToAccelerator();
        #ifndef NDEBUG
          #{vector}->Check();
        #endif
        // result
        #{result} = new LocalVector<#{system_code.cresult}>;
        #{result}->Allocate("x", neq);
        // solver
        #{solver} = new #{solverType};
        #{solver}->Init(#{@solver.absolute_tolerance}, #{@solver.relative_tolerance}, 1e+8 /* as in manual */, #{@solver.max_steps});
        #{solver}->SetOperator(*#{matrix});
        #{pc} = new #{pcType};
        #{solver}->SetPreconditioner(*#{pc});
        #{solver}->Build();
        #{solver}->MoveToAccelerator();
        #ifndef NDEBUG
          #{matrix}->info();
          #{vector}->info();
        #endif
        double tac = paralution_time();
        std::cout << "System setup time " << (tac-tic)/1000000 << " seconds" << std::endl;
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
        delete [] #{mvals};
      $
      super
    end
    def write_defs(stream)
      super
      stream << %$
        static void #{examineStatus}(void) {
          FINITA_ENTER;
          int status = #{solver}->GetSolverStatus();
          if(status != 1 && status != 2) FINITA_FAILURE("Paralution solver failed to converge");
          FINITA_LEAVE;
        }
      $
      @solver.linear? ? write_solve_linear(stream) : write_solve_nonlinear(stream)
    end
    def write_solve_linear(stream)
      stream << %$
        void #{system_code.solve}(void) {
          FINITA_ENTER;
          double tic = paralution_time();
          #{SparsityPatternCode.it} it;
          // matrix
          int index = 0;
          #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
          while(#{SparsityPatternCode.itMove}(&it)) {
            const #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
            #{mvals}[index++] = #{lhs_code.evaluate}(coord.row, coord.column);
          }
          #{matrix}->MoveToHost();
          #{matrix}->Zeros();
          #{matrix}->AssembleUpdate(#{mvals});
          #{matrix}->MoveToAccelerator();
          #ifndef NDEBUG
            #{matrix}->Check();
          #endif
          const int neq = #{mapper_code.size}();
          // vector
          #{vector}->MoveToHost();
          #{vector}->LeaveDataPtr(&#{vvals});
          for(index = 0; index < neq; ++index) {
            #{vvals}[index] = -#{rhs_code.evaluate}(#{mapper_code.node}(index));
          }
          #{vector}->SetDataPtr(&#{vvals}, "b", neq);
          #{vector}->MoveToAccelerator();
          #ifndef NDEBUG
            #{vector}->Check();
          #endif
          // result
          #{result}->Zeros();
          #{result}->MoveToAccelerator();
          // solver
          #{solver}->ResetOperator(*#{matrix});
          #{solver}->Solve(*#{vector}, #{result}); #{examineStatus}();
          // result
          #{result}->MoveToHost();
          #{result}->LeaveDataPtr(&#{vvals});
          for(index = 0; index < neq; ++index) {
            #{mapper_code.indexSet}(index, #{vvals}[index]);
          }
          #{result}->SetDataPtr(&#{vvals}, "x", neq);
          #{decomposer_code.synchronizeUnknowns}();
          double tac = paralution_time();
          std::cout << "System solution time " << (tac-tic)/1000000 << " seconds" << std::endl;
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
          double tic = paralution_time();
          const int neq = #{mapper_code.size}();
          do {
            double norm, base = 0, delta = 0; /* TODO : complex */
            // matrix
            #{SparsityPatternCode.itCtor}(&it, &#{sparsity});
            int index = 0;
            while(#{SparsityPatternCode.itMove}(&it)) {
              const #{NodeCoordCode.type} coord = #{SparsityPatternCode.itGet}(&it);
              #{mvals}[index++] = #{jacobian_code.evaluate}(coord.row, coord.column);
            }
            #{matrix}->MoveToHost();
            #{matrix}->Zeros();
            #{matrix}->AssembleUpdate(#{mvals});
            #{matrix}->MoveToAccelerator();
            #ifndef NDEBUG
              #{matrix}->Check();
            #endif
            // vector
            #{vector}->MoveToHost();
            #{vector}->LeaveDataPtr(&#{vvals});
            for(index = 0; index < neq; ++index) {
              #{vvals}[index] = -#{residual_code.evaluate}(#{mapper_code.node}(index));
            }
            #{vector}->SetDataPtr(&#{vvals}, "b", neq);
            #{vector}->MoveToAccelerator();
            #ifndef NDEBUG
              #{vector}->Check();
            #endif
            // result
            #{result}->Zeros();
            #{result}->MoveToAccelerator();
            // solver
            #{solver}->ResetOperator(*#{matrix});
            #{solver}->Solve(*#{vector}, #{result}); #{examineStatus}();
            // result
            #{result}->MoveToHost();
            #{result}->LeaveDataPtr(&#{vvals});
            for(index = 0; index < neq; ++index) {
              const #{system_code.cresult} value = #{mapper_code.indexGet}(index), dvalue = #{vvals}[index];
              base += #{abs}(value);
              delta += #{abs}(dvalue);
              #{mapper_code.indexSet}(index, value + dvalue);
            }
            #{result}->SetDataPtr(&#{vvals}, "x", neq);
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
          double tac = paralution_time();
          std::cout << "System solution time " << (tac-tic)/1000000 << " seconds" << std::endl;
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
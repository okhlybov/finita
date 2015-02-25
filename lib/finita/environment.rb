require "autoc"
require "singleton"
require "finita/problem"


module Finita


class Environment
  def seq?; is_a?(Sequential) end
  def mpi?; is_a?(MPI) end
  def omp?; is_a?(OpenMP) end
  class Code < Finita::Code
    def initialize(prefix, seq, mpi, omp)
      super(prefix)
      @seq = seq
      @mpi = mpi
      @omp = omp
    end
    def priority; AutoC::Priority::MAX end
    def seq?; @seq end
    def mpi?; @mpi end
    def omp?; @omp end
  end
end # Environment


class Environment::Sequential < Environment
  StaticCode = Class.new(Environment::Code) do
    def write_intf(stream)
      stream << %$
        #define FINITA_SEQ
      $
    end
  end.new(:FinitaSEQ, true, false, false)
  def code(problem_code)
    StaticCode
  end
end # Sequential


class Environment::OpenMP < Environment
  StaticCode = Class.new(Environment::Code) do
    def write_intf(stream)
      stream << %$
        #define FINITA_OMP
      $
    end
  end.new(:FinitaOMP, false, false, true)
  def code(problem_code)
    StaticCode
  end
end # OpenMP


class Environment::MPI < Environment
  StaticCode = Class.new(Environment::Code) do
    def write_intf(stream)
      stream << %$
        #define FINITA_MPI
        extern int FinitaProcessCount, FinitaProcessIndex;
      $
    end
    def write_defs(stream)
      stream << %$int FinitaProcessCount, FinitaProcessIndex;$
    end
    def write_initializer(stream)
      stream << %${
        int ierr, flag;
        FINITA_ENTER;
        ierr =  MPI_Initialized(&flag); #{assert}(ierr == MPI_SUCCESS);
        if(!flag) {
          ierr = MPI_Init(&argc, &argv); #{assert}(ierr == MPI_SUCCESS);
        }
        ierr = MPI_Comm_size(MPI_COMM_WORLD, &FinitaProcessCount); #{assert}(ierr == MPI_SUCCESS);
        ierr = MPI_Comm_rank(MPI_COMM_WORLD, &FinitaProcessIndex); #{assert}(ierr == MPI_SUCCESS);
        FINITA_LEAVE;
      }$
    end
    def write_finalizer(stream)
      stream << %${
        int ierr, flag;
        FINITA_ENTER;
        ierr =  MPI_Finalized(&flag); #{assert}(ierr == MPI_SUCCESS);
        if(!flag) {
          ierr = MPI_Finalize(); #{assert}(ierr == MPI_SUCCESS);
        }
        FINITA_LEAVE;
      }$
    end
  end.new(:FinitaMPI, false, true, false)
  def code(problem_code)
    problem_code.initializer_codes << StaticCode
    problem_code.finalizer_codes << StaticCode
    StaticCode
  end
end # MPI


end # Finita
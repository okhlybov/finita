require "autoc"
require "singleton"
require "finita/problem"


module Finita


class Environment
  def seq?; is_a?(Sequential) end
  def mpi?; is_a?(MPI) end
  def omp?; is_a?(OpenMP) end
end # Environment


class Environment::Sequential < Environment
  Tag = :seq
  def code(problem_code)
    problem_code.defines << :FINITA_SEQ
    Code.instance
  end
  class Code < AutoC::Code
    include Singleton # TODO convert to anonymous class
    def priority
      AutoC::Priority::DEFAULT + 1
    end
    def seq?; true end
    def mpi?; false end
    def omp?; false end
  end
end # Sequential


class Environment::MPI < Environment
  Tag = :mpi
  def code(problem_code)
    problem_code.defines << :FINITA_MPI
    problem_code.initializer_codes << Code.instance
    problem_code.finalizer_codes << Code.instance
    Code.instance
  end
  class Code < AutoC::Code
    include Singleton
    def priority
      AutoC::Priority::DEFAULT + 1
    end
    def seq?; false end
    def mpi?; true end
    def omp?; false end
    def initialize
      super("FinitaMPI")
    end
    def write_intf(stream)
      stream << %$extern int FinitaProcessCount, FinitaProcessIndex;$
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
  end
end # MPI


class Environment::OpenMP < Environment
  Tag = :omp
  def code(problem_code)
    problem_code.defines << :FINITA_OMP
    Code.instance
  end
  class Code < AutoC::Code
    include Singleton
    def priority
      AutoC::Priority::DEFAULT + 1
    end
    def seq?; false end
    def mpi?; false end
    def omp?; true end
  end
end # OpenMP


end # Finita
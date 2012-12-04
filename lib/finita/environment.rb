require 'singleton'
require 'data_struct'
require 'finita/problem'


module Finita


module EnvironmentHandler
  def setup_env(env)
    @environment_tag = env.class::Tag
  end
  def seq?; @environment_tag == Environment::Sequential::Tag end
  def mpi?; @environment_tag == Environment::MPI::Tag end
  def omp?; @environment_tag == Environment::OpenMP::Tag end
end


class Environment
end # Environment


class Environment::Sequential < Environment
  Tag = :seq
  def code(problem_code)
    Code.instance
  end
  class Code < CodeBuilder::Code
    include Singleton
  end
end # Sequential


class Environment::MPI < Environment
  Tag = :mpi
  def code(problem_code)
    problem_code.defines << :FINITA_MPI
    problem_code.initializers << Code.instance
    problem_code.finalizers << Code.instance
    Code.instance
  end
  class Code < DataStruct::Code
    include Singleton
    def initialize
      super('FinitaMPI')
    end
    def write_intf(stream)
      stream << %$
        extern int FinitaProcessCount, FinitaProcessIndex;
      $
    end
    def write_defs(stream)
      stream << %$
        int FinitaProcessCount, FinitaProcessIndex;
      $
    end
    def write_initializer(stream)
      stream << %${
        int ierr, flag;
        ierr =  MPI_Initialized(&flag); #{assert}(ierr == MPI_SUCCESS);
        if(!flag) {
          ierr = MPI_Init(&argc, &argv); #{assert}(ierr == MPI_SUCCESS);
        }
        ierr = MPI_Comm_size(MPI_COMM_WORLD, &FinitaProcessCount); #{assert}(ierr == MPI_SUCCESS);
        ierr = MPI_Comm_rank(MPI_COMM_WORLD, &FinitaProcessIndex); #{assert}(ierr == MPI_SUCCESS);
      }$
    end
    def write_finalizer(stream)
      stream << %${
        int ierr, flag;
        ierr =  MPI_Finalized(&flag); #{assert}(ierr == MPI_SUCCESS);
        if(!flag) {
          ierr = MPI_Finalize(); #{assert}(ierr == MPI_SUCCESS);
        }
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
  class Code < CodeBuilder::Code
    include Singleton
  end
end # OpenMP


end # Finita
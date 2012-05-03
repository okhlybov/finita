require 'singleton'
require 'code_builder'
require 'finita/common'


module Finita::Environment


class Environment
  class StaticCode < Finita::StaticCodeTemplate
    def priority; CodeBuilder::Priority::MAX end
  end # StaticCode
end # Environment


class Serial < Environment
  class StaticCode < Environment::StaticCode
  end # StaticCode
  def static_code; StaticCode.instance end
  def bind(gtor)
    gtor << static_code
    gtor.defines << :FINITA_SERIAL
  end
end # Serial


class OpenMP < Environment
  class StaticCode < Environment::StaticCode
    def write_intf(stream)
      stream << %$
        #include <omp.h>
      $
    end
  end # Code
  def static_code; StaticCode.instance end
  def bind(gtor)
    gtor << static_code
    gtor.defines << :FINITA_OPENMP
  end
end # OpenMP


class MPI < Environment
  class StaticCode < Environment::StaticCode
    def write_intf(stream)
      stream << %$
        #include <mpi.h>
      $
    end
    def write_defs(stream)
      stream << %$
        int FinitaMPISize, FinitaMPIRank;
      $
    end
    def write_setup(stream)
      stream << %$
        {
          int result, flag;
          result = MPI_Initialized(&flag); FINITA_ASSERT(result == MPI_SUCCESS);
          if(!flag) {
            result = MPI_Init(&argc, &argv); FINITA_ASSERT(result == MPI_SUCCESS);
          }
          result = MPI_Comm_size(MPI_COMM_WORLD, &FinitaMPISize); FINITA_ASSERT(result == MPI_SUCCESS);
          result = MPI_Comm_rank(MPI_COMM_WORLD, &FinitaMPIRank); FINITA_ASSERT(result == MPI_SUCCESS);
        }
      $
    end
    def write_cleanup(stream)
      stream << %$
        {
          int result, flag;
          result = MPI_Finalized(&flag); FINITA_ASSERT(result == MPI_SUCCESS);
          if(!flag) {
            result = MPI_Finalize(); FINITA_ASSERT(result == MPI_SUCCESS);
          }
        }
      $
    end
  end # Code
  def static_code; StaticCode.instance end
  def bind(gtor)
    gtor << static_code
    gtor.defines << :FINITA_MPI
  end
end # MPI


end # Finita::Environment
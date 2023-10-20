# frozen_string_literal: true


require 'autoc/std'
require 'autoc/module'
require 'autoc/composite'


module Finita


  OMP_H = AutoC::Code.new interface: %{
    #ifdef _OPENMP
      #include <omp.h>
    #endif
  }


  MPI_H = AutoC::Code.new interface: %{
    #include <mpi.h>
  }


  class Workload < AutoC::Composite

    #include AutoC::Type::Standalone

    def copyable? = false
    def comparable? = false
    def orderable? = false
  
    def initialize(*args, **kws)
      super
      dependencies << AutoC::STD::ASSERT_H << OMP_H
    end

    def configure
      super
      method(:unsigned, :processes, { target: const_rvalue }).configure do
        header %{
          @brief Return total number of processes participating in the workload
        }
      end
      method(:unsigned, :process, { target: const_rvalue }).configure do
        header %{
          @brief Return current process index
        }
      end
    end

  end # Workload


  class Workload::Uniprocess < Workload

    def render_interface(stream)
      super
      stream << %{
        typedef struct {
          unsigned threads;
        } #{signature};
      }
    end

    def configure
      super
      destroy.inline_code %{}
      default_create.inline_code %{
        assert(target);
        target->threads =
          #ifdef _OPENMP
            omp_get_num_threads();
          #else
            1
          #endif
        ;
      }
      processes.inline_code %{return 1;}
      process.inline_code %{return 0;}
    end

  end # Uniprocess


  class Workload::Multiprocess < Workload

    def render_interface(stream)
      super
      stream << %{
        /**
          @brief
        */
        typedef struct {
          unsigned* process_threads; //< threads per process
          unsigned processes; //< process count
        } #{signature};
      }
    end

    def initialize(*args)
      super
      dependencies << MPI_H
    end
    
    def configure
      super
      destroy.code %{
        assert(target);
        #{memory.free('target->process_threads')};
      }
      default_create.code %{
        assert(target);

      }
    end

  end # Hybrid


end
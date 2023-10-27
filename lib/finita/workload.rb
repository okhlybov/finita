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
          @brief Return total number of processes sharing the workload
        }
      end
      method(:unsigned, :process, { target: const_rvalue }).configure do
        header %{
          @brief Return current process index
        }
      end
      method(:unsigned, :threads, { target: const_rvalue }).configure do
        header %{
          @brief Return total number of threads sharing the workload on the current process
        }
      end
      method(:unsigned, :thread, { target: const_rvalue }).configure do
        header %{
          @brief Return current per-process thread index
        }
      end
    end

  end # Workload


  class Workload::Uniprocess < Workload

    def render_interface(stream)
      super
      stream << %{
        typedef struct {
          unsigned threads; ///< @private
        } #{signature};
      }
    end

    def configure
      super
      destroy.code %{}
      default_create.code %{
        assert(target);
        #ifdef _OPENMP
          #pragma omp parallel
          #pragma omp single
          target->threads = omp_get_num_threads(); // capture default thread count when run in OMP parallel
        #else
          target->threads = 1;
        #endif
      }
      processes.inline_code %{return 1;}
      process.inline_code %{return 0;}
      threads.inline_code %{
        assert(target);
        return target->threads;
      }
      thread.inline_code %{
        assert(target);
        return
          #ifdef _OPENMP
            omp_get_thread_num();
          #else
            0
          #endif
        ;
      }
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
          unsigned* process_threads; //< @private
          unsigned processes; //< @ptivate
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
        // TODO
      }
    end

  end # Hybrid


end
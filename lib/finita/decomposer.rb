require "autoc"
require "finita/mapper"


module Finita


class Decomposer
  def process!(solver)
    @solver = check_type(solver, Solver)
    self
  end
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < DataStructBuilder::Code
    attr_reader :solver_code
    attr_reader :mapper_code
    def initialize(decomposer, solver_code)
      @decomposer = check_type(decomposer, Decomposer)
      @solver_code = check_type(solver_code, Solver::Code)
      @mapper_code = check_type(solver_code.mapper_code, Mapper::Code)
      super("#{solver_code.system_code.type}Decomposer")
      @numeric_array_code = NumericArrayCode[solver_code.system_code.result] if solver_code.mpi?
      solver_code.system_code.initializer_codes << self
    end
    def entities
      @entities.nil? ? @entities = super + [@mapper_code, @numeric_array_code].compact : @entities
    end
    def write_intf(stream)
      stream << %$
        void #{setup}(void);
        size_t #{firstIndex}(void);
        size_t #{lastIndex}(void);
        size_t #{indexCount}(void);
        void #{synchronizeUnknowns}(void);
      $
      stream << %$
        void #{synchronizeArray}(#{@numeric_array_code.type}*);
        void #{gatherArray}(#{@numeric_array_code.type}*);
        void #{scatterArray}(#{@numeric_array_code.type}*);
      $ if solver_code.mpi?
    end
    def write_defs(stream)
      super
      solver_code.mpi? ? write_defs_mpi(stream) : write_defs_nompi(stream)
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
    private
    def write_defs_mpi(stream)
      sc = solver_code.system_code
      ctype = CType[sc.result]
      mpi_ctype = MPIType[sc.result]
      stream << %$
        static int* #{counts};
        static int* #{offsets};
        size_t #{firstIndex}(void) {
          return #{offsets}[FinitaProcessIndex];
        }
        size_t #{lastIndex}(void) {
          return #{offsets}[FinitaProcessIndex] + #{counts}[FinitaProcessIndex] - 1;
        }
        size_t #{indexCount}(void) {
          return #{counts}[FinitaProcessIndex];
        }
        void #{synchronizeUnknowns}(void) {
          size_t index, count, process;
          #{@numeric_array_code.type} array;
          FINITA_ENTER;
          #{@numeric_array_code.ctor}(&array, #{@mapper_code.size}());
          for(index = #{firstIndex}(); index <= #{lastIndex}(); ++index) {
            #{@numeric_array_code.set}(&array, index, #{@mapper_code.indexGet}(index));
          }
          #{synchronizeArray}(&array);
          for(process = 0; process < FinitaProcessCount; ++process) {
            if(process != FinitaProcessIndex) {
              for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                #{@mapper_code.indexSet}(index, #{@numeric_array_code.get}(&array, index));
              }
            }
          }
          #{@numeric_array_code.dtor}(&array);
          FINITA_LEAVE;
        }
        void #{synchronizeArray}(#{@numeric_array_code.type}* array) {
          int ierr, index, count, process;
          #{ctype} *input, *real, *imaginary;
          FINITA_ENTER;
          input = (#{ctype}*)#{malloc}(#{indexCount}()*sizeof(#{ctype})); #{assert}(input);
          real = (#{ctype}*)#{malloc}(#{@mapper_code.size}()*sizeof(#{ctype})); #{assert}(real);
        $
      if sc.complex?
        stream << %$
          imaginary = (#{ctype}*)#{malloc}(#{NodeCodeArray.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(imaginary);
          for(count = 0, index = #{firstIndex}(); count < #{indexCount}(); ++count, ++index) {
            input[count] = creal(#{@numeric_array_code.get}(array, index));
          }
          ierr = MPI_Allgatherv(input, #{indexCount}(), #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          for(count = 0, index = #{firstIndex}(); count < #{indexCount}(); ++count, ++index) {
            input[count] = cimag(#{@numeric_array_code.get}(array, index));
          }
          ierr = MPI_Allgatherv(input, #{indexCount}(), #{mpi_ctype}, imaginary, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          for(process = 0; process < FinitaProcessCount; ++process) {
            if(process != FinitaProcessIndex) {
              for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                #{@numeric_array_code.set}(array, index, real[index] + _Complex_I*imaginary[index]);
              }
            }
          }
          #{free}(imaginary);
        $
      else
        stream << %$
          for(count = 0, index = #{firstIndex}(); count < #{indexCount}(); ++count, ++index) {
            input[count] = #{@numeric_array_code.get}(array, index);
          }
          ierr = MPI_Allgatherv(input, #{indexCount}(), #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          for(process = 0; process < FinitaProcessCount; ++process) {
            if(process != FinitaProcessIndex) {
              for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                #{@numeric_array_code.set}(array, index, real[index]);
              }
            }
          }
        $
      end
      stream << %$
        #{free}(real);
        #{free}(input);
        FINITA_LEAVE;
      }$
      stream << %$
        void #{gatherArray}(#{@numeric_array_code.type}* array) {
          int ierr, index, count, process;
          #{ctype} *input, *real, *imaginary;
          FINITA_ENTER;
          input = (#{ctype}*)#{malloc}(#{indexCount}()*sizeof(#{ctype})); #{assert}(input);
          real = (#{ctype}*)#{malloc}(#{@mapper_code.size}()*sizeof(#{ctype})); #{assert}(real);
      $
      if sc.complex?
        stream << %$
          imaginary = (#{ctype}*)#{malloc}(#@mapper_code.size}()*sizeof(#{ctype})); #{assert}(imaginary);
          FINITA_NHEAD for(count = 0, index = #{firstIndex}(); count < #{indexCount}(); ++count, ++index) {
            input[count] = creal(#{@numeric_array_code.get}(array, index));
          }
          ierr = MPI_Gatherv(input, #{indexCount}(), #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          FINITA_NHEAD for(count = 0, index = #{firstIndex}(); count < #{indexCount}(); ++count, ++index) {
            input[count] = cimag(#{@numeric_array_code.get}(array, index));
          }
          ierr = MPI_Gatherv(input, #{indexCount}(), #{mpi_ctype}, imaginary, #{counts}, #{offsets}, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          FINITA_HEAD for(process = 1; process < FinitaProcessCount; ++process) {
            for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
              #{@numeric_array_code.set}(array, index, real[index] + _Complex_I*imaginary[index]);
            }
          }
          #{free}(imaginary);
        $
      else
        stream << %$
            FINITA_NHEAD for(count = 0, index = #{firstIndex}(); count < #{indexCount}(); ++count, ++index) {
              input[count] = #{@numeric_array_code.get}(array, index);
            }
            ierr = MPI_Gatherv(input, #{indexCount}(), #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            FINITA_HEAD for(process = 1; process < FinitaProcessCount; ++process) {
              for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                #{@numeric_array_code.set}(array, index, real[index]);
              }
            }
          $
      end
      stream << %$
        #{free}(real);
        #{free}(input);
        FINITA_LEAVE;
      }$
      stream << %$
        void #{scatterArray}(#{@numeric_array_code.type}* array) {
          int ierr, count, index, process;
          #{ctype} *output, *real, *imaginary;
          FINITA_ENTER;
          size_t size = #{@mapper_code.size}();
          output = (#{ctype}*)#{malloc}(size*sizeof(#{ctype})); #{assert}(output);
          real = (#{ctype}*)#{malloc}(size*sizeof(#{ctype})); #{assert}(real);
      $
      if sc.complex?
        stream << %$
          imaginary = (#{ctype}*)#{malloc}(size*sizeof(#{ctype})); #{assert}(imaginary);
          FINITA_HEAD for(index = 0; index < size; ++index) {
            output[index] = creal(#{@numeric_array_code.get}(array, index));
          }
          ierr = MPI_Scatterv(output, #{counts}, #{offsets}, #{mpi_ctype}, real, #{indexCount}(), #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          FINITA_HEAD for(count = 0, index = #{firstIndex}(); count < #{indexCount}(); ++count, ++index) {
            output[index] = cimag(#{@numeric_array_code.get}(array, index));
          }
          ierr = MPI_Scatterv(output, #{counts}, #{offsets}, #{mpi_ctype}, imaginary, #{indexCount}(), #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          FINITA_NHEAD for(process = 1; process < FinitaProcessCount; ++process) {
            for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
              #{@numeric_array_code.set}(array, index, real[index] + _Complex_I*imaginary[index]);
            }
          }
          #{free}(imaginary);
        $
      else
        stream << %$
          FINITA_HEAD for(index = 0; index < size; ++index) {
            output[index] = #{@numeric_array_code.get}(array, index);
          }
          ierr = MPI_Scatterv(output, #{counts}, #{offsets}, #{mpi_ctype}, real, #{indexCount}(), #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          FINITA_NHEAD for(process = 1; process < FinitaProcessCount; ++process) {
            for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
              #{@numeric_array_code.set}(array, index, real[index]);
            }
          }
        $
      end
      stream << %$
        #{free}(real);
        #{free}(output);
        FINITA_LEAVE;
      }$
      stream << %$
        void #{broadcastArray}(#{@numeric_array_code.type}* array) {
          int ierr, count, index, process;
          #{ctype} *real, *imaginary;
          FINITA_ENTER;
          size_t size = #{@mapper_code.size}();
          real = (#{ctype}*)#{malloc}(size*sizeof(#{ctype})); #{assert}(real);
      $
      if sc.complex?
        stream << %$
          imaginary = (#{ctype}*)#{malloc}(size*sizeof(#{ctype})); #{assert}(imaginary);
          FINITA_HEAD for(index = 0; index < size; ++index) {
            real[index] = creal(#{@numeric_array_code.get}(array, index));
          }
          ierr = MPI_Bcast(real, size, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          FINITA_HEAD for(index = 0; index < size; ++index) {
            imaginary[index] = cimag(#{@numeric_array_code.get}(array, index));
          }
          ierr = MPI_Bcast(imaginary, size, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          FINITA_NHEAD for(index = 0; index < size; ++index) {
            #{@numeric_array_code.set}(array, index, real[index] + _Complex_I*imaginary[index]);
          }
          #{free}(imaginary);
        $
      else
        stream << %$
          FINITA_HEAD for(index = 0; index < size; ++index) {
            real[index] = #{@numeric_array_code.get}(array, index);
          }
          ierr = MPI_Bcast(real, size, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
          FINITA_NHEAD for(index = 0; index < size; ++index) {
            #{@numeric_array_code.set}(array, index, real[index]);
          }
        $
      end
      stream << %$
        #{free}(real);
        FINITA_LEAVE;
      }$
    end
    def write_defs_nompi(stream)
      stream << %$
        size_t #{firstIndex}(void) {return 0;}
        size_t #{lastIndex}(void) {return #{@mapper_code.size}()-1;}
        size_t #{indexCount}(void) {return #{@mapper_code.size}();}
        void #{synchronizeUnknowns}() {}
      $
    end
  end # Code
end # Decomposer


class Decomposer::Naive < Decomposer
  class Code < Decomposer::Code
    def write_defs(stream)
      super
      if solver_code.mpi?
        stream << %$
          void #{setup}(void) {
            FINITA_ENTER;
            size_t index, base_index, process, size = #{@mapper_code.size}();
            #{counts} = (int*)#{malloc}(FinitaProcessCount*sizeof(int)); #{assert}(#{counts});
            #{offsets} = (int*)#{malloc}(FinitaProcessCount*sizeof(int)); #{assert}(#{offsets});
            for(base_index = process = index = 0; index < size; ++index) {
              if(process < FinitaProcessCount*index/size) {
                #{offsets}[process] = base_index;
                #{counts}[process] = index - base_index;
                base_index = index;
                ++process;
              }
            }
            #{offsets}[process] = base_index;
            #{counts}[process] = index - base_index;
            FINITA_LEAVE;
          }
        $
      else
        stream << %$void #{setup}(void) {}$
      end
    end
  end # Code
end # Naive


end # finita
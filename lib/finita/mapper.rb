require "autoc"
require "finita/symbolic"
require "finita/environment"


module Finita


class Mapper
  attr_reader :unknowns
  attr_reader :mappings
  def process!(solver)
    @solver = check_type(solver, Solver)
    @unknowns = @solver.system.unknowns.to_a # ordered list
    @mappings = @solver.system.equations.collect do |e|
      [e.domain, e.unknown]
    end
    self
  end
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < DataStructBuilder::Code
    def initialize(mapper, solver_code)
      @mapper = check_type(mapper, Mapper)
      @solver_code = check_type(solver_code, Solver::Code)
      super("#{solver_code.system_code.type}Mapper")
      @numeric_array_code = NumericArrayCode[solver_code.system_code.result] if solver_code.mpi?
    end
    def entities
      super + [NodeCode, @numeric_array_code].compact
    end
    attr_reader :solver_code
    def write_intf(stream)
      sc = solver_code.system_code
      stream << %$
        #{NodeCode.type} #{node}(size_t);
        int #{hasNode}(#{NodeCode.type});
        size_t #{index}(#{NodeCode.type});
        void #{indexSet}(size_t, #{sc.cresult});
        #{sc.cresult} #{indexGet}(size_t);
        void #{nodeSet}(#{NodeCode.type}, #{sc.cresult});
        #{sc.cresult} #{nodeGet}(#{NodeCode.type});
        size_t #{size}(void);
        size_t #{firstIndex}(void);
        size_t #{lastIndex}(void);
        void #{synchronize}(void);
      $
    end
    def write_defs(stream)
      sc = solver_code.system_code
      stream << %$
        void #{nodeSet}(#{NodeCode.type} node, #{sc.cresult} value) {
          switch(node.field) {
      $
      x = -1
      @mapper.unknowns.each do |u|
        stream << %$case #{x+=1}: #{u.name}(node.x, node.y, node.z) = value; break;$
      end
      stream << %$default: #{abort}();$
      stream << %$}}$
      stream << %$
        #{sc.cresult} #{nodeGet}(#{NodeCode.type} node) {
          switch(node.field) {
      $
      x = -1
      @mapper.unknowns.each do |u|
        stream << %$case #{x+=1}: return #{u.name}(node.x, node.y, node.z);$
      end
      stream << %$default: #{abort}();$
      stream << %$} return 0;}$
      stream << %$
        void #{indexSet}(size_t index, #{sc.cresult} value) {
          #{nodeSet}(#{node}(index), value);
        }
        #{sc.cresult} #{indexGet}(size_t index) {
          return #{nodeGet}(#{node}(index));
        }
      $
      stream << %$
        static #{NodeArrayCode.type} #{nodes};
        static #{NodeIndexMapCode.type} #{indices};
        int #{hasNode}(#{NodeCode.type} node) {
          return #{NodeIndexMapCode.containsKey}(&#{indices}, node);
        }
        #{NodeCode.type} #{node}(size_t index) {
          return #{NodeArrayCode.get}(&#{nodes}, index);
        }
        size_t #{index}(#{NodeCode.type} node) {
          return #{NodeIndexMapCode.get}(&#{indices}, node);
        }
      $
      if solver_code.mpi?
        stream << %$
          static int* #{counts};
          static int* #{offsets};
          static void #{bcastOrdering}(void) {
            int size;
            int ierr, index, position;
            int packed_entry_size, packed_buffer_size;
            void *packed_buffer;
            #{NodeCode.type} node;
            FINITA_HEAD size = #{NodeIndexMapCode.size}(&#{indices});
            ierr = MPI_Bcast(&size, 1, MPI_INT, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            FINITA_NHEAD #{NodeArrayCode.ctor}(&#{nodes}, size);
            ierr = MPI_Pack_size(4, MPI_INT, MPI_COMM_WORLD, &packed_entry_size); #{assert}(ierr == MPI_SUCCESS);
            packed_buffer_size = packed_entry_size*size;
            packed_buffer = #{malloc}(packed_buffer_size); #{assert}(packed_buffer);
            FINITA_HEAD {
              for(position = index = 0; index < size; ++index) {
                node = #{NodeArrayCode.get}(&#{nodes}, index);
                ierr = MPI_Pack(&node.field, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Pack(&node.x, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Pack(&node.y, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Pack(&node.z, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
              }
            }
            ierr = MPI_Bcast(packed_buffer, packed_buffer_size, MPI_PACKED, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            FINITA_NHEAD {
              for(position = index = 0; index < size; ++index) {
                int field, x, y, z;
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &field, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &x, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &y, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &z, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                node = FinitaNodeNew(field, x, y, z);
                #{NodeArrayCode.set}(&#{nodes}, index, node);
                #{NodeIndexMapCode.put}(&#{indices}, node, index);
              }
            }
            #{free}(packed_buffer);
        }$
      end
      if solver_code.mpi?
        sc = solver_code.system_code
        ctype = CType[sc.result]
        mpi_ctype = MPIType[sc.result]
        stream << %$
          void #{synchronize}(void) {
            int ierr, index, count, process;
            #{ctype} *input, *real;
            #{ctype} *imaginary;
            input = (#{ctype}*)#{malloc}(#{counts}[FinitaProcessIndex]*sizeof(#{ctype})); #{assert}(input);
            real = (#{ctype}*)#{malloc}(#{NodeArrayCode.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(real);
        $
        if sc.complex?
          stream << %$
            imaginary = (#{ctype}*)#{malloc}(#{NodeArrayCode.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(imaginary);
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = creal(#{indexGet}(index));
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = cimag(#{indexGet}(index));
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, imaginary, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            for(process = 0; process < FinitaProcessCount; ++process) {
              if(process != FinitaProcessIndex) {
                for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                  #{indexSet}(index, real[index] + _Complex_I*imaginary[index]);
                }
              }
            }
            #{free}(imaginary);
          $
        else
          stream << %$
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = #{indexGet}(index);
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            for(process = 0; process < FinitaProcessCount; ++process) {
              if(process != FinitaProcessIndex) {
                for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                  #{indexSet}(index, real[index]);
                }
              }
            }
          $
        end
        stream << "}"
        stream << %$
          void #{synchronizeArray}(#{@numeric_array_code.type}* array) {
            int ierr, index, count, process;
            #{ctype} *input, *real, *imaginary;
            input = (#{ctype}*)#{malloc}(#{counts}[FinitaProcessIndex]*sizeof(#{ctype})); #{assert}(input);
            real = (#{ctype}*)#{malloc}(#{NodeArrayCode.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(real);
        $
        if sc.complex?
          stream << %$
            imaginary = (#{ctype}*)#{malloc}(#{NodeCodeArray.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(imaginary);
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = creal(#{@numeric_array_code.get}(array, index));
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = cimag(#{@numeric_array_code.get}(array, index));
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, imaginary, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
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
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = #{@numeric_array_code.get}(array, index);
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
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
        }$
        stream << %$
          void #{gatherArray}(#{@numeric_array_code.type}* array) {
            int ierr, index, count, process;
            #{ctype} *input, *real, *imaginary;
            input = (#{ctype}*)#{malloc}(#{counts}[FinitaProcessIndex]*sizeof(#{ctype})); #{assert}(input);
            real = (#{ctype}*)#{malloc}(#{NodeArrayCode.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(real);
        $
        if sc.complex?
          stream << %$
            imaginary = (#{ctype}*)#{malloc}(#{NodeArrayCode.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(imaginary);
            FINITA_NHEAD for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = creal(#{@numeric_array_code.get}(array, index));
            }
            ierr = MPI_Gatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            FINITA_NHEAD for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = cimag(#{@numeric_array_code.get}(array, index));
            }
            ierr = MPI_Gatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, imaginary, #{counts}, #{offsets}, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            FINITA_HEAD for(process = 1; process < FinitaProcessCount; ++process) {
              for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                #{@numeric_array_code.set}(array, index, real[index] + _Complex_I*imaginary[index]);
              }
            }
            #{free}(imaginary);
          $
        else
          stream << %$
            FINITA_NHEAD for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = #{@numeric_array_code.get}(array, index);
            }
            ierr = MPI_Gatherv(input, #{counts}[FinitaProcessIndex], #{mpi_ctype}, real, #{counts}, #{offsets}, #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
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
        }$
        stream << %$
          void #{scatterArray}(#{@numeric_array_code.type}* array) {
            int ierr, count, index, process;
            #{ctype} *output, *real, *imaginary;
            size_t size = #{size}();
            output = (#{ctype}*)#{malloc}(#{NodeArrayCode.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(output);
            real = (#{ctype}*)#{malloc}(#{NodeArrayCode.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(real);
        $
        if sc.complex?
          stream << %$
            imaginary = (#{ctype}*)#{malloc}(#{NodeArrayCode.size}(&#{nodes})*sizeof(#{ctype})); #{assert}(imaginary);
            FINITA_HEAD for(index = 0; index < size; ++index) {
              output[index] = creal(#{@numeric_array_code.get}(array, index));
            }
            ierr = MPI_Scatterv(output, #{counts}, #{offsets}, #{mpi_ctype}, real, #{counts}[FinitaProcessIndex], #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            FINITA_HEAD for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              output[index] = cimag(#{@numeric_array_code.get}(array, index));
            }
            ierr = MPI_Scatterv(output, #{counts}, #{offsets}, #{mpi_ctype}, imaginary, #{counts}[FinitaProcessIndex], #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
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
            ierr = MPI_Scatterv(output, #{counts}, #{offsets}, #{mpi_ctype}, real, #{counts}[FinitaProcessIndex], #{mpi_ctype}, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
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
        }$
        stream << %$
          size_t #{firstIndex}(void) {
            return #{offsets}[FinitaProcessIndex];
          }
          size_t #{lastIndex}(void) {
            return #{offsets}[FinitaProcessIndex] + #{counts}[FinitaProcessIndex] - 1;
          }
          size_t #{size}(void) {
            return #{NodeArrayCode.size}(&#{nodes});
          }
        $
      else
        stream << %$
          void #{synchronize}(void) {}
          size_t #{firstIndex}(void) {
            return 0;
          }
          size_t #{lastIndex}(void) {
            return #{size}()-1;
          }
          size_t #{size}(void) {
            return #{NodeArrayCode.size}(&#{nodes});
          }
        $
      end
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # Mapper


end # Finita


require "finita/mapper/naive"
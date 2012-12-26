require 'data_struct'
require 'finita/symbolic'
require 'finita/environment'


module Finita


class Mapper
  include EnvironmentHandler
  attr_reader :fields, :domains
  def process!(solver)
    setup_env(solver.environment)
  end
  def code(problem_code, system_code)
    self.class::Code.new(self, problem_code, system_code)
  end
  class Code < DataStruct::Code
    attr_reader :mapper
    def entities
      super + [@node]
    end
    def initialize(mapper, problem_code, system_code)
      @mapper = mapper
      @problem_code = problem_code
      @system_code = system_code
      @node = NodeCode.instance
      @result = @system_code.result
      @system_code.initializers << self
      super("#{system_code.type}Mapping")
    end
    def hash
      mapper.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && mapper == other.mapper
    end
    def write_intf(stream)
      stream << %$
        size_t #{size}(void);
        #{@node.type} #{getNode}(size_t);
        size_t #{getIndex}(#{@node.type});
        #{@result} #{getValue}(size_t index);
        void #{setValue}(size_t index, #{@result} value);
        void #{synchronize}(void);
        int #{firstIndex}(void);
        int #{lastIndex}(void);
      $
    end
  end
end # Mapper


class Mapper::Naive < Mapper
  attr_reader :mappings, :solver
  def process!(problem, system, solver)
    super(solver)
    @fields = system.equations.collect {|e| e.unknown}.uniq # an ordered list of unknown fields in the system
    @domains = Set.new(system.equations.collect {|e| e.domain}) # a set of domains in the system
    @mappings = system.equations.collect {|e| [e.unknown, e.domain]}
  end
  class Code < Mapper::Code
    def entities
      super + [@nodeArray, @nodeSet, @nodeMap] + fields
    end
    def initialize(*args)
      super
      @nodeArray = NodeArrayCode.instance
      @nodeSet = NodeSetCode.instance
      @nodeMap = NodeIndexMapCode.instance
    end
    def fields
      mapper.fields.collect {|f| f.code(@problem_code)}
    end
    def write_intf(stream)
      super
      stream << %$int #{setup}(void);$
      stream << %$
      #{inline} void #{nodeSet}(#{@node.type} node, #{@result} value) {
          switch(node.field) {
        $
      index = 0
      mapper.fields.each do |field|
        stream << %$case #{index}: #{field.name}(node.x, node.y, node.z) = value; break;$
        index += 1
      end
      stream << %$default : #{abort}();$
      stream << '}}'
      stream << %$
      #{inline} #{@result} #{nodeGet}(#{@node.type} node) {
          #{@result} value;
          switch(node.field) {
      $
      index = 0
      mapper.fields.each do |field|
        stream << %$case #{index}: value = #{field.name}(node.x, node.y, node.z); break;$
        index += 1
      end
      stream << %$default : #{abort}();$
      stream << '}return value;}'
    end
    def write_defs(stream)
      field_codes = mapper.fields.collect {|field| field.code(@problem_code)}
      domain_codes = mapper.domains.collect {|domain| domain.code(@problem_code)}
      stream << %$
        static int* #{counts};
        static int* #{offsets};
      $ if mapper.mpi?
      stream << %$
        static #{@nodeArray.type} #{nodes};
        static #{@nodeMap.type} #{indices};
        size_t #{size}(void) {
          return #{@nodeArray.size}(&#{nodes});
        }
        int #{setup}(void) {
          int index, size;
          #{@nodeSet.type} nodes;
      $
      stream << %$
          FINITA_HEAD {
            size_t approx_node_count = 1;
      $
      domain_codes.each {|domain| stream << %$approx_node_count += #{domain.size}(&#{domain.instance});$}
      stream << %$#{@nodeSet.ctor}(&nodes, approx_node_count*#{field_codes.size});$
      mapper.mappings.each do |f,d|
        domain = d.code(@problem_code) # TODO get rid of excessive code object creation
        stream << %${
          #{domain.it} it;
          #{domain.itCtor}(&it, &#{domain.instance});
          while(#{domain.itHasNext}(&it)) {
            #{domain.node} node = #{domain.itNext}(&it);
            #{@nodeSet.put}(&nodes, #{@node.new}(#{mapper.fields.index(f)}, node.x, node.y, node.z));
          }
        }$
      end
      stream << %$
          size = #{@nodeSet.size}(&nodes);
        }
      $
      if mapper.mpi?
        stream << %${
          int ierr = MPI_Bcast(&size, 1, MPI_INT, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
        }$
      end
      stream << %$
        #{@nodeArray.ctor}(&#{nodes}, size);
        #{@nodeMap.ctor}(&#{indices}, size);
      $
      stream << %$FINITA_HEAD {
        #{@nodeSet.it} it;
        index = 0;
        #{@nodeSet.itCtor}(&it, &nodes);
        while(#{@nodeSet.itHasNext}(&it)) {
          #{@node.type} node = #{@nodeSet.itNext}(&it);
          #{@nodeArray.set}(&#{nodes}, index, node);
          #{@nodeMap.put}(&#{indices}, node, index);
          ++index;
        }
        }
      $
      if mapper.mpi?
        stream << %$
          {
            int ierr, index, position;
            int packed_entry_size, packed_buffer_size;
            void *packed_buffer;
            #{@node.type} node;
            ierr = MPI_Pack_size(4, MPI_INT, MPI_COMM_WORLD, &packed_entry_size); #{assert}(ierr == MPI_SUCCESS);
            packed_buffer_size = packed_entry_size*size;
            packed_buffer = #{malloc}(packed_buffer_size); #{assert}(packed_buffer);
            FINITA_HEAD {
              for(position = index = 0; index < size; ++index) {
                node = #{@nodeArray.get}(&#{nodes}, index);
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
                #{@nodeArray.set}(&#{nodes}, index, node);
                #{@nodeMap.put}(&#{indices}, node, index);
              }
            }
            #{free}(packed_buffer);
          }
        $
        if mapper.mpi?
          stream << %${
          int base_index, process;
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
        }$
        end
      end
      stream << 'return FINITA_OK;}'
      if mapper.mpi?
        if @system_code.system.type == Complex
          c_type = Finita::NumericType[Float]
          mpi_type = Finita::MPIType[Float]
        else
          c_type = @result
          mpi_type = Finita::MPIType[@system_code.system.type]
        end
        stream << %$
          void #{synchronize}(void) {
            int ierr, index, count, process;
            #{c_type} *input, *real;
            input = (#{c_type}*)#{malloc}(#{counts}[FinitaProcessIndex]*sizeof(#{c_type})); #{assert}(input);
            real = (#{c_type}*)#{malloc}(#{@nodeArray.size}(&#{nodes})*sizeof(#{c_type})); #{assert}(real);
        $
        if @system_code.system.type == Complex
          stream << %${
            #{c_type} *imaginary;
            imaginary = (#{c_type}*)#{malloc}(#{@nodeArray.size}(&#{nodes})*sizeof(#{c_type})); #{assert}(imaginary);
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = creal(#{getValue}(index));
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_type}, real, #{counts}, #{offsets}, #{mpi_type}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = cimag(#{getValue}(index));
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_type}, imaginary, #{counts}, #{offsets}, #{mpi_type}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            for(process = 0; process < FinitaProcessCount; ++process) {
              if(process != FinitaProcessIndex) {
                for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                  #{setValue}(index, real[index] + _Complex_I*imaginary[index]);
                }
              }
            }
            #{free}(imaginary);
          }$
        else
          stream << %$
            for(count = 0, index = #{offsets}[FinitaProcessIndex]; count < #{counts}[FinitaProcessIndex]; ++count, ++index) {
              input[count] = #{getValue}(index);
            }
            ierr = MPI_Allgatherv(input, #{counts}[FinitaProcessIndex], #{mpi_type}, real, #{counts}, #{offsets}, #{mpi_type}, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            for(process = 0; process < FinitaProcessCount; ++process) {
              if(process != FinitaProcessIndex) {
                for(count = 0, index = #{offsets}[process]; count < #{counts}[process]; ++count, ++index) {
                  #{setValue}(index, real[index]);
                }
              }
            }
          $
        end
        stream << %$
            #{free}(real);
            #{free}(input);
          }
          int #{firstIndex}(void) {
            return #{offsets}[FinitaProcessIndex];
          }
          int #{lastIndex}(void) {
            return #{offsets}[FinitaProcessIndex] + #{counts}[FinitaProcessIndex] - 1;
          }
        $
      else
        stream << %$
          void #{synchronize}(void) {}
          int #{firstIndex}(void) {
            return 0;
          }
          int #{lastIndex}(void) {
            return #{size}() - 1;
          }
        $
      end
      stream << %$
        #{@result} #{getValue}(size_t index) {
          return #{nodeGet}(#{@nodeArray.get}(&#{nodes}, index));
        }
        void #{setValue}(size_t index, #{@result} value) {
          #{nodeSet}(#{@nodeArray.get}(&#{nodes}, index), value);
        }
      $
      stream << %$
        #{@node.type} #{getNode}(size_t index) {
          return #{@nodeArray.get}(&#{nodes}, index);
        }
        size_t #{getIndex}(#{@node.type} node) {
          return #{@nodeMap.get}(&#{indices}, node);
        }
      $
      super
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end
end # Naive


end # Finita
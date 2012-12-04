require 'data_struct'
require 'finita/type'
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
      result = super + [@node]
      result << @intList if mapper.mpi?
      result
    end
    def initialize(mapper, problem_code, system_code)
      @mapper = mapper
      @problem_code = problem_code
      @system_code = system_code
      @node = NodeCode.instance
      @intList = IntegerListCode.instance if mapper.mpi?
      @result = @system_code.result
      @system_code.initializers << self
      super("#{system_code.type}Mapper")
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
      $
      stream << (mapper.mpi? ? "void #{synchronize}(void);" : "FINITA_INLINE void #{synchronize}(void) {}")
      stream << (mapper.mpi? ? "void #{synchronizerSetup}(void);" : "FINITA_INLINE void #{synchronizerSetup}(void) {}")
    end
    def write_defs(stream)
      if mapper.mpi?
        # blocks is an array of [size, i0, i1,...] that is
        # *blocks[i] is size of line i, *(blocks[i]+1) is i0 of line i and so forth
        stream << %$
          static int** #{blocks};
          void #{synchronize}(void) {

          }
          void #{synchronizerSetup}(void) {
            int index, size = #{@intArray.size}(&#{affinity});
            #{@intList.type}* list = (#{@intList.type}*)#{malloc}(FinitaProcessCount*sizeof(#{@intList.type})); #{assert}(list);
            #{blocks} = (int**)#{malloc}(FinitaProcessCount*sizeof(int*)); #{assert}(#{blocks});
            for(index = 0; index < FinitaProcessCount; ++index) {
              #{@intList.ctor}(&list[index]);
            }
            for(index = 0; index < size; ++index) {
              #{@intList.append}(&list[#{@intArray.get}(&#{affinity}, index)], index);
            }
            for(index = 0; index < FinitaProcessCount; ++index) {
              #{@intList.it} it;
              int i = 0, size = #{@intList.size}(&list[index]);
              #{blocks}[index] = (int*)#{malloc}((size+1)*sizeof(int)); #{assert}(#{blocks}[index]);
              #{blocks}[index][0] = size;
              #{@intList.itCtor}(&it, &list[index]);
              while(#{@intList.itHasNext}(&it)) {
                #{blocks}[index][++i] = #{@intList.itNext}(&it);
              }
            }
          }
        $
      end
    end
  end
end # Mapper


class Mapper::Naive < Mapper
  attr_reader :mappings, :solver
  def process!(problem, system, solver)
    super(solver)
    index = -1
    @fields = system.equations.collect {|e| e.unknown}.uniq # an ordered list of unknown fields in the system
    @domains = Set.new(system.equations.collect {|e| e.domain}) # a set of domains in the system
    @mappings = system.equations.collect {|e| [e.unknown, e.domain]}
  end
  class Code < Mapper::Code
    def entities
      result = super + [@nodeArray, @nodeSet, @nodeMap] + fields
      result << @intArray if mapper.mpi?
      result
    end
    def initialize(*args)
      super
      @intArray = IntegerArrayCode.instance if mapper.mpi?
      @nodeArray = NodeArrayCode.instance
      @nodeSet = NodeSetCode.instance
      @nodeMap = NodeIndexMapCode.instance
    end
    def fields
      mapper.fields.collect {|f| f.code(@problem_code)}
    end
    def write_intf(stream)
      stream << %$int #{setup}(void);$
      super
    end
    def write_defs(stream)
      field_codes = mapper.fields.collect {|field| field.code(@problem_code)}
      domain_codes = mapper.domains.collect {|domain| domain.code(@problem_code)}
      stream << %$
        static #{@intArray.type} #{affinity};
      $ if mapper.mpi?
      stream << %$
        static #{@nodeArray.type} #{nodes};
        static #{@nodeMap.type} #{indices};
        size_t #{size}(void) {
          return #{@nodeArray.size}(&#{nodes});
        }
        int #{setup}(void) {
          int index, size;
          FINITA_HEAD {
            #{@nodeSet.type} nodes;
            {
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
      stream << %$}{
        #{@nodeSet.it} it;
        index = 0;
        size = #{@nodeSet.size}(&nodes);
        #{@nodeArray.ctor}(&#{nodes}, size);
        #{@nodeMap.ctor}(&#{indices}, size);
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
          #{@intArray.ctor}(&#{affinity}, size);
          for(index = 0; index < size; ++index) {
            #{@intArray.set}(&#{affinity}, index, FinitaProcessCount*index/size);
          }
        $
      end
      stream << '}'
      if mapper.mpi?
        stream << %$
          {
            int ierr, index, position, process;
            int packed_entry_size, packed_buffer_size;
            void *packed_buffer;
            #{@node.type} node;
            ierr = MPI_Bcast(&size, 1, MPI_INT, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            ierr = MPI_Pack_size(5, MPI_INT, MPI_COMM_WORLD, &packed_entry_size); #{assert}(ierr == MPI_SUCCESS);
            packed_buffer_size = packed_entry_size*size;
            packed_buffer = #{malloc}(packed_buffer_size); #{assert}(packed_buffer);
            FINITA_HEAD {
              for(position = index = 0; index < size; ++index) {
                node = #{@nodeArray.get}(&#{nodes}, index);
                process = #{@intArray.get}(&#{affinity}, index);
                ierr = MPI_Pack(&node.field, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Pack(&node.x, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Pack(&node.y, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Pack(&node.z, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Pack(&process, 1, MPI_INT, packed_buffer, packed_buffer_size, &position, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
              }
            }
            ierr = MPI_Bcast(packed_buffer, packed_buffer_size, MPI_PACKED, 0, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
            FINITA_NHEAD {
              for(position = index = 0; index < size; ++index) {
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &node.field, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &node.x, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &node.y, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &node.z, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                ierr = MPI_Unpack(packed_buffer, packed_buffer_size, &position, &process, 1, MPI_INT, MPI_COMM_WORLD); #{assert}(ierr == MPI_SUCCESS);
                #{@nodeArray.set}(&#{nodes}, index, node);
                #{@nodeMap.put}(&#{indices}, node, index);
                #{@intArray.set}(&#{affinity}, index, process);
              }
            }
            #{free}(packed_buffer);
          }
          #{synchronizerSetup}();
        $
      end
      stream << 'return FINITA_OK;}'
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
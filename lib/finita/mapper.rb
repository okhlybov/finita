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
      @entities.nil? ? @entities = super + [NodeCode, @numeric_array_code].compact : @entities
    end
    attr_reader :solver_code
    def write_intf(stream)
      sc = solver_code.system_code
      stream << %$
        size_t #{size}(void);
        #{NodeCode.type} #{node}(size_t);
        int #{hasNode}(#{NodeCode.type});
        size_t #{index}(#{NodeCode.type});
        void #{indexSet}(size_t, #{sc.cresult});
        #{sc.cresult} #{indexGet}(size_t);
        void #{nodeSet}(#{NodeCode.type}, #{sc.cresult});
        #{sc.cresult} #{nodeGet}(#{NodeCode.type});
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
        size_t #{size}(void) {
          return #{NodeArrayCode.size}(&#{nodes});
        }
      $
      if solver_code.mpi?
        stream << %$
          static void #{broadcastOrdering}(void) {
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
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # Mapper


class Mapper::Naive < Mapper
  class Code < Mapper::Code
    def initialize(mapper, solver_code)
      super
      solver_code.system_code.initializer_codes << self
      pc = solver_code.system_code.problem_code
      @unknown_codes = @mapper.unknowns.collect {|u| check_type(u.code(pc), Field::Code)}
      @domain_codes = []
      @mapping_codes = @mapper.mappings.collect do |m|
        dc = m.first.code(pc)
        @domain_codes << dc
        [dc, @mapper.unknowns.index(m.last)]
      end
    end
    def entities
      @entities.nil? ? @entities = super + [NodeArrayCode, NodeIndexMapCode] + @domain_codes : @entities
    end
    def write_intf(stream)
      super
      stream << %$void #{setup}(void);$
    end
    def write_defs(stream)
      super
      stream << %$
        void #{setup}(void) {size_t index = 0; #{NodeIndexMapCode.ctor}(&#{indices}); FINITA_HEAD {
      $
      @mapping_codes.each do |mc|
        dc, f = mc
        stream << %${
          #{dc.it} it;
          #{dc.itCtor}(&it, &#{dc.instance});
          while(#{dc.itHasNext}(&it)) {
            #{dc.node} coord = #{dc.itNext}(&it);
            if(#{NodeIndexMapCode.put}(&#{indices}, #{NodeCode.new}(#{f}, coord.x, coord.y, coord.z), index)) ++index;
          }
        }$
      end
      stream << %${
        #{NodeIndexMapCode.it} it;
        #{NodeArrayCode.ctor}(&#{nodes}, #{NodeIndexMapCode.size}(&#{indices}));
        #{NodeIndexMapCode.itCtor}(&it, &#{indices});
        while(#{NodeIndexMapCode.itHasNext}(&it)) {
          #{NodeIndexMapCode.entry} entry = #{NodeIndexMapCode.itNext}(&it);
          #{NodeArrayCode.set}(&#{nodes}, entry.value, entry.key);
        }
      }}$
      stream << %$#{broadcastOrdering}();$ if solver_code.mpi?
      stream << "}"
    end
  end # Code
end # Naive


end # Finita
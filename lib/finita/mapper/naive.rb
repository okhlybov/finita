module Finita


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
      super + [NodeArrayCode, NodeIndexMapCode] + @domain_codes
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
      stream << %${
        int base_index, process;
        int size = #{NodeArrayCode.size}(&#{nodes});
        #{counts} = (int*)#{malloc}(FinitaProcessCount*sizeof(int)); #{assert}(#{counts});
        #{offsets} = (int*)#{malloc}(FinitaProcessCount*sizeof(int)); #{assert}(#{offsets});
        for(base_index = process = index = 0; index < size; ++index) {
          if(process < FinitaProcessCount*index/size) {
            #{offsets}[process] = base_index;
            #{counts}[process] = index - base_index;
            base_index = index;
            ++process;
          }
          #{offsets}[process] = base_index;
          #{counts}[process] = index - base_index + 1;
        }
      }$ if solver_code.mpi?
      stream << "}"
    end
  end # Code
end # Naive


end # Finita
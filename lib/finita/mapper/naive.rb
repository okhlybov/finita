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
        static #{NodeArrayCode.type} #{nodes};
        static #{NodeIndexMapCode.type} #{indices};
        void #{sync}(void) {}
        size_t #{firstIndex}(void) {
          return 0;
        }
        size_t #{lastIndex}(void) {
          return #{size}()-1;
        }
        size_t #{size}(void) {
          return #{NodeArrayCode.size}(&#{nodes});
        }
        int #{hasNode}(#{NodeCode.type} node) {
          return #{NodeIndexMapCode.containsKey}(&#{indices}, node);
        }
        #{NodeCode.type} #{node}(size_t index) {
          return #{NodeArrayCode.get}(&#{nodes}, index);
        }
        size_t #{index}(#{NodeCode.type} node) {
          return #{NodeIndexMapCode.get}(&#{indices}, node);
        }
        void #{setup}(void) {size_t index = 0; #{NodeIndexMapCode.ctor}(&#{indices});
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
    end
  end # Code
end # Naive


end # Finita
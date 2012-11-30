require 'data_struct'
require 'finita/type'


module Finita


class Mapper
  attr_reader :fields # ordered list expected
  def code(problem_code, system_code)
    self.class::Code.new(self, problem_code, system_code)
  end
  class Code < DataStruct::Code
    attr_reader :mapper
    def initialize(mapper, problem_code, system_code)
      @mapper = mapper
      @problem_code = problem_code
      @system_code = system_code
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
      #{@result} #{read}(size_t index);
        void #{write}(size_t index, #{@result} value);
      $
    end
  end
end # Mapper


class Mapper::Naive < Mapper
  def process!(system) end
  class Code < Mapper::Code
    def entities; super + [@node, @nodeArray, @nodeSet, @nodeMap] end
    def initialize(*args)
      super
      @node = NodeCode.instance
      @nodeArray = NodeArrayCode.instance
      @nodeSet = NodeSetCode.instance
      @nodeMap = NodeIndexMapCode.instance
    end
    def write_intf(stream)
      super
      stream << %$
        int #{setup}(void);
      $
    end
    def write_defs(stream)
      node = NodeCode.instance
      equation_codes = @system_code.equation_codes
      domain_codes = equation_codes.collect {|e| e.domain_code}.uniq
      unknown_codes = equation_codes.collect {|e| e.unknown_code}.uniq
      stream << %$
        static #{@nodeArray.type} #{nodes};
        static #{@nodeMap.type} #{indices};
        int #{setup}(void) {
          #{@nodeSet.type} nodes;
          {size_t approx_node_count = 1;
        $
      domain_codes.each do |d|
        stream << %$approx_node_count += #{d.size}(&#{d.instance});$
      end
      stream << %$
        #{@nodeSet.ctor}(&nodes, approx_node_count*#{unknown_codes.size});
      $
     equation_codes.each do |e|
        domain = e.domain_code
        stream << %${
          #{domain.it} it;
          #{domain.itCtor}(&it, &#{domain.instance});
          while(#{domain.itHasNext}(&it)) {
            #{domain.node} node = #{domain.itNext}(&it);
            #{@nodeSet.put}(&nodes, #{node.new}(#{unknown_codes.index(e.unknown_code)}, node.x, node.y, node.z));
          }
        }$
     end
      stream << %$}{
        size_t index = 0;
        #{@nodeSet.it} it;
        #{@nodeArray.ctor}(&#{nodes}, #{@nodeSet.size}(&nodes));
        #{@nodeMap.ctor}(&#{indices}, #{@nodeSet.size}(&nodes));
        #{@nodeSet.itCtor}(&it, &nodes);
        while(#{@nodeSet.itHasNext}(&it)) {
          #{@node.type} node = #{@nodeSet.itNext}(&it);
          #{@nodeArray.set}(&#{nodes}, index, node);
          #{@nodeMap.put}(&#{indices}, node, index);
          ++index;
        }
      }$
      stream << 'return FINITA_OK;}'
      stream << %$
        #{inline} void #{nodeSet}(#{@node.type} node, #{@result} value) {
          switch(node.field) {
        $
        index = 0
        unknown_codes.each do |u|
          stream << %$case #{index}: #{u.symbol}(node.x, node.y, node.z) = value; break;$
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
      unknown_codes.each do |u|
        stream << %$case #{index}: value = #{u.symbol}(node.x, node.y, node.z); break;$
        index += 1
      end
      stream << %$default : #{abort}();$
      stream << '}return value;}'
      stream << %$
        #{@result} #{read}(size_t index) {
          return #{nodeGet}(#{@nodeArray.get}(&#{nodes}, index));
        }
        void #{write}(size_t index, #{@result} value) {
          #{nodeSet}(#{@nodeArray.get}(&#{nodes}, index), value);
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end
end # Naive


end # Finita
require 'data_struct'
require 'finita/type'


module Finita


class Mapper
  attr_reader :fields, :domains
  def code(problem_code, system_code)
    self.class::Code.new(self, problem_code, system_code)
  end
  class Code < DataStruct::Code
    attr_reader :mapper
    def entities; super + [@node] end
    def initialize(mapper, problem_code, system_code)
      @mapper = mapper
      @problem_code = problem_code
      @system_code = system_code
      @node = NodeCode.instance
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
    end
  end
end # Mapper


class Mapper::Naive < Mapper
  attr_reader :mappings
  def process!(problem, system)
    index = -1
    @fields = system.equations.collect {|e| e.unknown}.uniq # an ordered list of unknown fields in the system
    @domains = Set.new(system.equations.collect {|e| e.domain}) # a set of domains in the system
    @mappings = system.equations.collect {|e| [e.unknown, e.domain]}
  end
  class Code < Mapper::Code
    def entities; super + [@nodeArray, @nodeSet, @nodeMap] + fields end
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
      stream << %$
        int #{setup}(void);
      $
    end
    def write_defs(stream)
      field_codes = mapper.fields.collect {|field| field.code(@problem_code)}
      domain_codes = mapper.domains.collect {|domain| domain.code(@problem_code)}
      stream << %$
        static #{@nodeArray.type} #{nodes};
        static #{@nodeMap.type} #{indices};
        size_t #{size}(void) {
          return #{@nodeArray.size}(&#{nodes});
        }
        int #{setup}(void) {
          #{@nodeSet.type} nodes;
          {size_t approx_node_count = 1;
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
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end
end # Naive


end # Finita
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
    def entities
      super + [@node, @numericArray]
    end
    def initialize(mapper, problem_code, system_code)
      @mapper = mapper
      @problem_code = problem_code
      @system_code = system_code
      @node = NodeCode.instance
      @numericArray = NumericArrayCode[@system_code.type]
      @result = @system_code.result
      @system_code.initializers << self
      super("#{system_code.type}Mapping")
    end
    def hash
      @mapper.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @mapper == other.instance_variable_get(:@mapper)
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
        void #{synchronizeArray}(#{@numericArray.type}*);
        void #{gatherArray}(#{@numericArray.type}*);
        void #{scatterArray}(#{@numericArray.type}*);
      $
    end
  end
end # Mapper


end # Finita


require 'finita/mapper/naive'
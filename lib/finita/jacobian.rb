require 'data_struct'
require 'finita/evaluator'


module Finita


class Jacobian
  def process!(problem, system) end
  def code(problem_code, system_code, mapper_code)
    self.class::Code.new(self, problem_code, system_code, mapper_code)
  end
  class Code < DataStruct::Code
    def entities; super + [@mapper_code] end
    def initialize(jacobian, problem_code, system_code, mapper_code)
      @jacobian = jacobian
      @node = NodeCode.instance
      @problem_code = problem_code
      @system_code = system_code
      @mapper_code = mapper_code
      @system_code.initializers << self
      super("#{@system_code.type}Jacobian")
    end
    def hash
      @jacobian.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @jacobian == other.instance_variable_get(:@jacobian)
    end
    def write_intf(stream)
      stream << %$
        size_t #{size}(void);
        #{@coord.type} #{coord}(size_t);
        #{@system_code.result} #{value}(size_t);
      $
    end
  end # Code
end # Jacobian


end # Finita


require 'finita/jacobian/numeric'
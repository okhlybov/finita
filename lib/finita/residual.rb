require "autoc"
require "finita/evaluator"


module Finita


class Residual
  def process!(solver)
    @solver = check_type(solver, Solver::Matrix)
    self
  end
  attr_reader :solver
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < DataStructBuilder::Code
    def initialize(residual, solver_code)
      @residual = check_type(residual, Residual)
      @solver_code = check_type(solver_code, Solver::Matrix::Code)
      super("#{solver_code.system_code.type}Residual")
      sc = solver_code.system_code
      pc = sc.problem_code
      sc.initializer_codes << self
      @array_code = FunctionArrayCode[sc.result]
      @function_code = FunctionCode[sc.result]
      @function_list_code = FunctionListCode[sc.result]
      @mapping_codes = solver_code.mapping_codes
    end
    def entities
      super + [NodeCode, @array_code, @function_code, @function_list_code] + solver_code.all_dependent_codes
    end
    attr_reader :solver_code
    def hash
      @residual.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @residual == other.instance_variable_get(:@residual)
    end
    def write_intf(stream)
      stream << %$#{solver_code.system_code.cresult} #{evaluate}(#{NodeCode.type});$
    end
    def write_defs(stream)
      super
      mc = solver_code.mapper_code
      sc = solver_code.system_code
      stream << %$
        static #{@array_code.type} #{evaluators};
        void #{setup}(void) {
          size_t index, first = #{mc.firstIndex}(), last = #{mc.lastIndex}(), size = last - first + 1;
          #{@array_code.ctor}(&#{evaluators}, size);
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} node = #{mc.node}(index);
      $
      @mapping_codes.each do |mc|
        stream << %$
          if(node.field == #{mc[:unknown_index]} && #{mc[:domain_code].within}(&#{mc[:domain_code].instance}, node.x, node.y, node.z)) {
            #{@array_code.merge}(&#{evaluators}, index - first, #{mc[:residual_code].instance});
        $
        stream << "continue;" unless m
        stream << "}"
      end
      stream << "}}"
      stream << %$
        #{sc.cresult} #{evaluate}(#{NodeCode.type} row) {
          return #{@function_list_code.summate}(#{@array_code.get}(&#{evaluators}, #{mc.index}(row) - #{mc.firstIndex}()), row.x, row.y, row.z);
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # Residual


end
require "autoc"
require "finita/evaluator"


module Finita


class Residual
  def process!(solver)
    @solver = Finita.check_type(solver, Solver::Matrix)
    self
  end
  attr_reader :solver
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < Finita::Type
    def initialize(residual, solver_code)
      @residual = Finita.check_type(residual, Residual)
      @solver_code = Finita.check_type(solver_code, Solver::Matrix::Code)
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
      @entities.nil? ? @entities = super.concat([NodeCode, @array_code, @function_code, @function_list_code, solver_code.mapper_code, solver_code.decomposer_code] + solver_code.all_dependent_codes) : @entities
    end
    attr_reader :solver_code
    def hash
      @residual.hash # TODO
    end
    def ==(other)
      equal?(other) || self.class == other.class && @residual == other.instance_variable_get(:@residual)
    end
    alias :eql? :==
    def write_intf(stream)
      stream << %$#{extern} #{solver_code.system_code.cresult} #{evaluate}(#{NodeCode.type});$
    end
    def write_defs(stream)
      super
      mc = solver_code.mapper_code
      dc = solver_code.decomposer_code
      sc = solver_code.system_code
      stream << %$
        static #{@array_code.type} #{evaluators};
        void #{setup}(void) {
          size_t index, first, last, size;
          FINITA_ENTER;
          first = #{dc.firstIndex}();
          last = #{dc.lastIndex}();
          size = #{dc.indexCount}();
          #{@array_code.ctor}(&#{evaluators}, size);
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} node = #{mc.node}(index);
      $
      @mapping_codes.each do |mc|
        stream << %$
          if(node.field == #{mc[:unknown_index]} && #{mc[:domain_code].within}(&#{mc[:domain_code].instance}, node.x, node.y, node.z)) {
            #{@array_code.merge}(&#{evaluators}, index - first, #{mc[:residual_code].instance});
        $
        stream << "continue;" unless mc[:merge]
        stream << "}"
      end
      stream << "}FINITA_LEAVE;}"
      stream << %$
        #{sc.cresult} #{evaluate}(#{NodeCode.type} row) {
          #{sc.cresult} value;
          FINITA_ENTER;
          value = #{@function_list_code.summate}(#{@array_code.get}(&#{evaluators}, #{mc.index}(row) - #{dc.firstIndex}()), row.x, row.y, row.z);
          FINITA_RETURN(value);
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # Residual


end
require "autoc"
require "finita/evaluator"


module Finita


class RHS
  def process!(solver)
    @solver = check_type(solver, Solver::Matrix)
    self
  end
  attr_reader :solver
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < DataStructBuilder::Code
    def initialize(lhs, solver_code)
      @rhs = check_type(lhs, RHS)
      @solver_code = check_type(solver_code, Solver::Matrix::Code)
      super("#{solver_code.system_code.type}RHS")
      sc = solver_code.system_code
      pc = sc.problem_code
      @vector_code = SparseVectorCode[sc.result]
      @function_list_code = FunctionListCode[sc.result]
      @mapping_codes = solver_code.mapping_codes
      sc.initializer_codes << self
    end
    def entities
      super + [NodeCode, @vector_code, @function_list_code, solver_code.mapper_code, solver_code.decomposer_code] + solver_code.all_dependent_codes
    end
    attr_reader :solver_code
    def hash
      @rhs.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @rhs == other.instance_variable_get(:@rhs)
    end
    def write_intf(stream)
      stream << %$
        void #{setup}(void);
        #{solver_code.system_code.cresult} #{evaluate}(#{NodeCode.type});
      $
    end
    def write_defs(stream)
      mc = solver_code.mapper_code
      dc = solver_code.decomposer_code
      sc = solver_code.system_code
      stream << %$
        static #{@vector_code.type} #{vector};
        void #{setup}(void) {
          int x, y, z;
          size_t index, first, last;
          FINITA_ENTER;
          first = #{dc.firstIndex}();
          last = #{dc.lastIndex}();
          #{@vector_code.ctor}(&#{vector});
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} row = #{mc.node}(index);
            x = row.x; y = row.y; z = row.z;
      $
      @mapping_codes.each do |mc|
        stream << %$if(row.field == #{mc[:unknown_index]} && #{mc[:domain_code].within}(&#{mc[:domain_code].instance}, x, y, z)) {$
        stream << %$#{@vector_code.merge}(&#{vector}, row, #{mc[:rhs_codes][nil].instance});$
        mc[:rhs_codes].each do |r, ec|
          stream << %$
            if(!#{solver_code.mapper_code.hasNode}(#{NodeCode.new}(#{r[0]}, #{r[1]}, #{r[2]}, #{r[3]}))) {
              #{@vector_code.merge}(&#{vector}, row, #{ec.instance});
            }
          $ unless r.nil?
        end
        stream << "continue;" unless m
        stream << "}"
      end
      stream << "}FINITA_LEAVE;}"
      stream << %$
        #{sc.cresult} #{evaluate}(#{NodeCode.type} row) {
          #{sc.cresult} result;
          FINITA_ENTER;
          result = #{@function_list_code.summate}(#{@vector_code.get}(&#{vector}, row), row.x, row.y, row.z);
          FINITA_RETURN(result);
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # RHS


end
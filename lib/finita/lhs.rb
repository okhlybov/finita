require "autoc"
require "finita/evaluator"


module Finita


class LHS
  def process!(solver)
    @solver = check_type(solver, Solver::Matrix)
    self
  end
  attr_reader :solver
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < AutoC::Type
    def initialize(lhs, solver_code)
      @lhs = check_type(lhs, LHS)
      @solver_code = check_type(solver_code, Solver::Matrix::Code)
      super("#{solver_code.system_code.type}LHS")
      sc = solver_code.system_code
      @matrix_code = SparseMatrixCode[sc.result]
      @function_list_code = FunctionListCode[sc.result]
      @mapping_codes = solver_code.mapping_codes
      sc.initializer_codes << self
    end
    def entities
      @entities.nil? ? @entities = [NodeCode, @matrix_code, @function_list_code, solver_code.mapper_code, solver_code.decomposer_code] + solver_code.all_dependent_codes : @entities
    end
    attr_reader :solver_code
    def hash
      @lhs.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @lhs == other.instance_variable_get(:@lhs)
    end
    def write_intf(stream)
      stream << %$
        #{extern} void #{setup}(void);
        #{extern} #{solver_code.system_code.cresult} #{evaluate}(#{NodeCode.type}, #{NodeCode.type});
      $
    end
    def write_defs(stream)
      mc = solver_code.mapper_code
      dc = solver_code.decomposer_code
      sc = solver_code.system_code
      stream << %$
        static #{@matrix_code.type} #{matrix};
        void #{setup}(void) {
          int x, y, z;
          size_t index, first, last;
          FINITA_ENTER;
          first = #{dc.firstIndex}();
          last = #{dc.lastIndex}();
          #{@matrix_code.ctor}(&#{matrix});
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} column, row = #{mc.node}(index);
            x = row.x; y = row.y; z = row.z;
      $
      @mapping_codes.each do |mc|
        stream << %$if(row.field == #{mc[:unknown_index]} && #{mc[:domain_code].within}(&#{mc[:domain_code].instance}, x, y, z)) {$
        mc[:lhs_codes].each do |r, ec|
          stream << %$
            if(#{solver_code.mapper_code.hasNode}(column = #{NodeCode.new}(#{r[0]}, #{r[1]}, #{r[2]}, #{r[3]}))) {
              #{@matrix_code.merge}(&#{matrix}, row, column, #{ec.instance});
            }
          $
        end
        stream << "continue;" unless mc[:merge]
        stream << "}"
      end
      stream << "}"
      stream << %${
        FILE* file = fopen("#{matrix}.txt", "wt");
        #{@matrix_code.dumpStats}(&#{matrix}, file);
        fclose(file);
      }$ if $debug
      stream << "FINITA_LEAVE;}"
      abs = sc.complex? ? 'cabs' : 'abs'
      stream << %$
        #{sc.cresult} #{evaluate}(#{NodeCode.type} row, #{NodeCode.type} column) {
          #{sc.cresult} value;
          FINITA_ENTER;
          value = #{@function_list_code.summate}(#{@matrix_code.get}(&#{matrix}, #{NodeCoordCode.new}(row, column)), row.x, row.y, row.z);
          FINITA_RETURN(value);
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # LHS


end # Finita
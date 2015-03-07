require "autoc"
require "finita/evaluator"


module Finita


class Jacobian
  def process!(solver)
    @solver = Finita.check_type(solver, Solver::Matrix)
    self
  end
  attr_reader :solver
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < Finita::Code
    def initialize(jacobian, solver_code)
      @jacobian = Finita.check_type(jacobian, Jacobian)
      @solver_code = Finita.check_type(solver_code, Solver::Matrix::Code)
      super("#{solver_code.system_code.type}Jacobian")
    end
    def entities
      super.concat([NodeCode, solver_code.mapper_code, solver_code.decomposer_code] + solver_code.all_dependent_codes)
    end
    attr_reader :solver_code
    def hash
      @jacobian.hash # TODO
    end
    def ==(other)
      equal?(other) || self.class == other.class && @jacobian == other.instance_variable_get(:@jacobian)
    end
    alias :eql? :==
    def write_intf(stream)
      stream << %$#{extern} #{solver_code.system_code.cresult} #{evaluate}(#{NodeCode.type}, #{NodeCode.type});$
    end
  end # Code
end # Jacobian


class Jacobian::Numeric < Jacobian
  def initialize(rtol = 1e-9)
    @rtol = rtol
  end
  attr_reader :rtol
  class Code < Jacobian::Code
    def entities
      super.concat([@matrix_code, @function_code, @function_list_code])
    end
    def initialize(*args)
      super
      sc = solver_code.system_code
      sc.initializer_codes << self
      @matrix_code = SparseMatrixCode[sc.result]
      @function_code = FunctionCode[sc.result]
      @function_list_code = FunctionListCode[sc.result]
      @mapping_codes = solver_code.mapping_codes
    end
    def write_defs(stream)
      super
      mc = solver_code.mapper_code
      dc = solver_code.decomposer_code
      sc = solver_code.system_code
      stream << %$
        static #{@matrix_code.type} #{evaluators};
        void #{setup}(void) {
          int x, y, z;
          size_t index, first, last;
          FINITA_ENTER;
          first = #{dc.firstIndex}();
          last = #{dc.lastIndex}();
          #{@matrix_code.ctor}(&#{evaluators});
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} column, row = #{mc.node}(index);
            x = row.x; y = row.y; z = row.z;
      $
      @mapping_codes.each do |mc|
        stream << %$if(row.field == #{mc[:unknown_index]} && #{mc[:domain_code].within}(&#{mc[:domain_code].instance}, x, y, z)) {$
        mc[:jacobian_codes].each do |r, ec|
          stream << %$
            if(#{solver_code.mapper_code.hasNode}(column = #{NodeCode.new}(#{r[0]}, #{r[1]}, #{r[2]}, #{r[3]}))) {
              #{@matrix_code.merge}(&#{evaluators}, row, column, #{ec.instance});
            }
          $
        end
        stream << "continue;" unless mc[:merge]
        stream << "}"
      end
      stream << "}FINITA_LEAVE;}"
      cresult = sc.cresult
      rt = @jacobian.rtol
      abs = CAbs[sc.result]
      stream << %$
        #{cresult} #{evaluate}(#{NodeCode.type} row, #{NodeCode.type} column) {
          #{@function_list_code.type}* fps;
          #{cresult} result, original;
          FINITA_ENTER;
          result = 0;
          original = #{mc.nodeGet}(column);
          #{cresult} delta = #{abs}(original) > 100*#{rt} ? original*#{rt} : 100*pow(#{rt}, 2)*(original < 0 ? -1 : 1);
          fps = #{@matrix_code.get}(&#{evaluators}, #{NodeCoordCode.new}(row, column));
          #{mc.nodeSet}(column, original + delta);
          result += #{@function_list_code.summate}(fps, row.x, row.y, row.z);
          #{mc.nodeSet}(column, original - delta);
          result -= #{@function_list_code.summate}(fps, row.x, row.y, row.z);
          #{mc.nodeSet}(column, original);
          result /= 2*delta;
          FINITA_RETURN(result);
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # Numeric


end # Finita
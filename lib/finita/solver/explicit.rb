module Finita


class Solver::Explicit < Solver
  def initialize(*args)
    super
    raise "unsupported environment" unless environment.seq?
  end
  def process!(*args)
    super
    @unknowns = system.unknowns.to_a
    @mappings = system.equations.collect do |e|
      [Evaluator.new(e.assignment, system.result), e.domain, e.unknown]
    end
    self
  end
  attr_reader :mappings
  attr_reader :unknowns
  class Code < Solver::Code
    def entities
      super.concat([@array_code, @function_code, @function_list_code] + @evaluator_codes + @unknown_codes + @domain_codes)
    end
    def initialize(*args)
      super
      pc = system_code.problem_code
      system_code.initializer_codes << self
      @array_code = FunctionArrayCode[system_code.result]
      @function_code = FunctionCode[system_code.result]
      @function_list_code = FunctionListCode[system_code.result]
      @unknown_codes = @solver.unknowns.collect {|u| Finita.check_type(u.code(pc), Field::Code)}
      @evaluator_codes = []
      @domain_codes = []
      @mapping_codes = @solver.mappings.collect do |m|
        ec = Finita.check_type(m[0].code(pc), Evaluator::Code)
        dc = m[1].code(pc)
        @evaluator_codes << ec
        @domain_codes << dc
        [ec, dc, @solver.unknowns.index(m[2])]
      end
    end
    def write_intf(stream)
      super
      stream << %$#{extern} void #{setup}(void);$
    end
    def write_defs(stream)
      super
      stream << %$
        static #{@array_code.type} #{evaluators};
        void #{setup}(void) {
          size_t index, first, last, size;
          FINITA_ENTER;
          first = #{decomposer_code.firstIndex}();
          last = #{decomposer_code.lastIndex}();
          size = #{decomposer_code.indexCount}();
          #{@array_code.ctor}(&#{evaluators}, size);
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} node = #{mapper_code.node}(index);
      $
      @mapping_codes.each do |mc|
        ec, dc, f = mc
        stream << %$
          if(node.field == #{f} && #{dc.within}(&#{dc.instance}, node.x, node.y, node.z)) {
            #{@array_code.merge}(&#{evaluators}, index - first, #{ec.instance});
            continue;
          }
        $
      end
      stream << %$}FINITA_LEAVE;}$
      stream << %$
        void #{system_code.solve}(void) {
          size_t index, first, last;
          FINITA_ENTER;
          first = #{decomposer_code.firstIndex}();
          last = #{decomposer_code.lastIndex}();
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} node = #{mapper_code.node}(index);
            #{mapper_code.indexSet}(index, #{@function_list_code.summate}(#{@array_code.get}(&#{evaluators}, index - first), node.x, node.y, node.z));
          }
          #{decomposer_code.synchronizeUnknowns}();
          FINITA_LEAVE;
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # Explicit


end # Finita
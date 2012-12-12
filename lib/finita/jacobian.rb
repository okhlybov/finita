require 'data_struct'
require 'finita/evaluator'


module Finita


class Jacobian
  def process!(problem, system) end
  def code(problem_code, system_code, mapper_code)
    self.class::Code.new(self, problem_code, system_code, mapper_code)
  end
  class Code < DataStruct::Code
    attr_reader :jacobian
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
      jacobian.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && jacobian == other.jacobian
    end
    def write_intf(stream)
      stream << %$
        #{@system_code.result} #{evaluate}(#{@node.type}, #{@node.type});
      $
    end
  end # Code
end # Jacobian


class Jacobian::Numeric < Jacobian
  attr_reader :evaluators, :relative_tolerance
  def initialize(rtol)
    @relative_tolerance = rtol
  end
  def process!(problem, system)
    super
    @evaluators = system.equations.collect {|e| [Finita::Evaluator.new(e.equation, system.type, e.merge?), e.unknown, e.domain]}
  end
  class Code < Jacobian::Code
    def entities; super + [@matrix] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(*args)
      super
      @matrix = EvaluationMatrixCode[@system_code.system.type]
    end
    def evaluator_codes
      jacobian.evaluators.collect {|e| e.collect {|o| o.code(@problem_code)}}
    end
    def write_intf(stream)
      super
      stream << %$
        int #{setup}(void);
      $
    end
    def write_defs(stream)
      # TODO proper estimation of bucket size
      stream << %$
        static #{@matrix.type} #{matrix};
        int #{setup}(void) {
          int index, size = #{@mapper_code.size}(), first = #{@mapper_code.firstIndex}(), last = #{@mapper_code.lastIndex}();
          #{@matrix.ctor}(&#{matrix}, pow(last-first+1, 1.1));
          for(index = first; index <= last; ++index) {
            #{@node.type} row = #{@mapper_code.getNode}(index);
            int field = row.field, x = row.x, y = row.y, z = row.z;
        $
      evaluator_codes.each do |evaluator, field, domain|
        stream << %$
          if(field == #{@mapper_code.fields.index(field)} && #{domain.within}(&#{domain.instance}, x, y, z)) {
        $
        refs = ObjectCollector.new(Ref).apply!(evaluator.evaluator.expression)
        refs.keep_if {|r| @system_code.system.unknowns.include?(r.arg)}.each do |r|
          stream << %$
            #{@matrix.merge}(&#{matrix}, row, #{@node.new}(#{@mapper_code.mapper.fields.index(r.arg)}, #{r.xindex}, #{r.yindex}, #{r.zindex}), #{evaluator.instance});
          $
        end
        stream << (evaluator.merge? ? nil : 'continue;') << '}'
      end
      abs = @system_code.system.type == Complex ? 'cabs' : 'fabs'
      rt = jacobian.relative_tolerance
      stream << %$
          }
          return FINITA_OK;
        }
        #{@system_code.result} #{evaluate}(#{@node.type} row, #{@node.type} column) {
          #{@system_code.result} result = 0, original = #{@mapper_code.nodeGet}(column);
          #{@system_code.result} delta = #{abs}(original) > 100*#{rt} ? original*#{rt} : 100*pow(#{rt}, 2)*(original < 0 ? -1 : 1);
          #{@mapper_code.nodeSet}(column, original + delta);
          result += #{@matrix.get}(&#{matrix}, row, column);
          #{@mapper_code.nodeSet}(column, original - delta);
          result -= #{@matrix.get}(&#{matrix}, row, column);
          #{@mapper_code.nodeSet}(column, original);
          return result/(2*delta);
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end # Code
end # Numeric


end # Finita
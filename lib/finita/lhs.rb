require 'data_struct'
require 'finita/evaluator'


module Finita


class LHS
  attr_reader :evaluators
  def code(problem_code, system_code, mapper_code)
    self.class::Code.new(self, problem_code, system_code, mapper_code)
  end
  def process!(problem, system)
    @evaluators = []
    system.equations.each do |e|
      e.decomposition(system.unknowns).each do |r, x|
        @evaluators << [Evaluator.new(x, system.type, e.merge?), e.unknown, e.domain, r] unless r.nil?
      end

    end
  end
  class Code < DataStruct::Code
    attr_reader :lhs
    def entities; super + [@mapper_code, @matrix, @array] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(lhs, problem_code, system_code, mapper_code)
      @lhs = lhs
      @node = NodeCode.instance
      @problem_code = problem_code
      @system_code = system_code
      @mapper_code = mapper_code
      @matrix = MatrixCode[@system_code.system.type]
      @array = MatrixArrayCode[@system_code.system.type]
      @system_code.initializers << self
      super("#{@system_code.type}LHS")
    end
    def evaluator_codes
      lhs.evaluators.collect {|e| e[0..-2].collect {|o| o.code(@problem_code)}}
    end
    def hash
      lhs.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && lhs == other.lhs
    end
    def write_intf(stream)
      stream << %$
        int #{setup}(void);
        #{@system_code.result} #{evaluate}(#{@node.type}, #{@node.type});
      $
    end
    def write_defs(stream)
      # TODO proper estimation of bucket size
      stream << %$
        static #{@matrix.type} #{matrix};
        static #{@array.type} #{array};
        int #{setup}(void) {
          int index, size = #{@mapper_code.size}(), first = #{@mapper_code.firstIndex}(), last = #{@mapper_code.lastIndex}();
          #{@matrix.ctor}(&#{matrix}, pow(last-first+1, 1.1));
          for(index = first; index <= last; ++index) {
            #{@node.type} row = #{@mapper_code.getNode}(index);
            int field = row.field, x = row.x, y = row.y, z = row.z;
        $
      lhs.evaluators.each do |e, f, d, r|
        evaluator = e.code(@problem_code)
        field = f.code(@problem_code)
        domain = d.code(@problem_code)
        stream << %$
          if(field == #{@mapper_code.fields.index(field)} && #{domain.within}(&#{domain.instance}, x, y, z)) {
          #{@matrix.merge}(&#{matrix}, row, #{@node.new}(#{@mapper_code.mapper.fields.index(r.arg)}, #{r.xindex}, #{r.yindex}, #{r.zindex}), #{evaluator.instance});
        $
        stream << (evaluator.merge? ? nil : 'continue;') << '}'
      end
      abs = @system_code.system.type == Complex ? 'cabs' : 'fabs'
      stream << %$
          }
          #{@matrix.linearize}(&#{matrix}, &#{array});
          return FINITA_OK;
        }
        #{@system_code.result} #{evaluate}(#{@node.type} row, #{@node.type} column) {
          return #{@matrix.evaluate}(&#{matrix}, row, column);
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end # Code
end # LHS


end
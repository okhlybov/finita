require 'data_struct'
require 'finita/evaluator'


module Finita


class RHS
  attr_reader :evaluators
  def process!(problem, system)
    @evaluators = system.equations.collect do |e|
      d13n = e.decomposition(system.unknowns)
      [Evaluator.new(d13n.include?(nil) ? Finita.simplify(-d13n[nil]) : 0, system.type, e.merge?), e.unknown, e.domain]
    end
  end
  def code(problem_code, system_code, mapper_code)
    self.class::Code.new(self, problem_code, system_code, mapper_code)
  end
  class Code < DataStruct::Code
    attr_reader :rhs
    def entities; super + [@vector, @array] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(rhs, problem_code, system_code, mapper_code)
      @rhs = rhs
      @node = NodeCode.instance
      @problem_code = problem_code
      @system_code = system_code
      @mapper_code = mapper_code
      @vector = VectorCode[@system_code.system.type]
      @array = VectorArrayCode[@system_code.system.type]
      @system_code.initializers << self
      super("#{@system_code.type}RHS")
    end
    def hash
      rhs.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && rhs == other.rhs
    end
    def evaluator_codes
      rhs.evaluators.collect {|e| e.collect {|o| o.code(@problem_code)}}
    end
    def write_intf(stream)
      stream << %$
        int #{setup}(void);
        #{@system_code.result} #{evaluate}(#{@node.type});
      $
    end
    def write_defs(stream)
      stream << %$
        static #{@vector.type} #{vector};
        static #{@array.type} #{array};
        int #{setup}(void) {
          int index, size = #{@mapper_code.size}(), first = #{@mapper_code.firstIndex}(), last = #{@mapper_code.lastIndex}();
          #{@vector.ctor}(&#{vector}, size);
          for(index = first; index <= last; ++index) {
            #{@node.type} node = #{@mapper_code.getNode}(index);
      $
      evaluator_codes.each do |evaluator, field, domain|
        merge_stmt = evaluator.merge? ? nil : 'continue;'
        stream << %$
          if(node.field == #{@mapper_code.fields.index(field)} && #{domain.within}(&#{domain.instance}, node.x, node.y, node.z)) {
            #{@vector.merge}(&#{vector}, node, #{evaluator.instance});
            #{merge_stmt}
          }
        $
      end
      stream << %$
          }
          #{@vector.linearize}(&#{vector}, &#{array});
          return FINITA_OK;
        }
        #{@system_code.result} #{evaluate}(#{@node.type} node) {
          return #{@vector.evaluate}(&#{vector}, node);
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end # Code
end # RHS


end
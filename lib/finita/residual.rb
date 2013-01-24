require 'data_struct'
require 'finita/evaluator'


module Finita


class Residual
  attr_reader :evaluators
  def process!(problem, system)
    @evaluators = system.equations.collect {|e| [Evaluator.new(e.equation, system.type), e.unknown, e.domain]}
  end
  def code(problem_code, system_code, mapper_code)
    self.class::Code.new(self, problem_code, system_code, mapper_code)
  end
  class Code < DataStruct::Code
    def entities; super + [@vector, @array] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(residual, problem_code, system_code, mapper_code)
      @residual = residual
      @node = NodeCode
      @problem_code = problem_code
      @system_code = system_code
      @mapper_code = mapper_code
      @vector = VectorCode[@system_code.system_type]
      @array = VectorArrayCode[@system_code.system_type]
      @entry = VectorEntryCode[@system_code.system_type]
      @system_code.initializers << self
      super("#{@system_code.type}Residual")
    end
    def hash
      @residual.hash # TODO
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @residual == other.instance_variable_get(:@residual)
    end
    def evaluator_codes
      @residual.evaluators.collect {|e| e.collect {|o| o.code(@problem_code)}}
    end
    def write_intf(stream)
      stream << %$
        int #{setup}(void);
        size_t #{size}(void);
        #{@node.type} #{node}(size_t);
        #{@system_code.result} #{value}(size_t);
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
      result = @system_code.result
      stream << %$
          }
          #{@vector.linearize}(&#{vector}, &#{array});
          return FINITA_OK;
        }
        #{result} #{value}(size_t index) {
          return #{@entry.evaluate}(#{@array.get}(&#{array}, index));
        }
        size_t #{size}(void) {
          return #{@array.size}(&#{array});
        }
        #{@node.type} #{node}(size_t index) {
          return #{@array.get}(&#{array}, index)->node;
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end # Code
end # Residual


end
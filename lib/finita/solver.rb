require 'finita/common'
require 'finita/system'
require 'finita/evaluator'
require 'finita/mapper'


module Finita


class Solver
  attr_reader :mapper
  def initialize(mapper)
    @mapper = mapper
  end
  def code(problem_code, system_code)
    self.class::Code.new(self, problem_code, system_code)
  end
  class Code < DataStruct::Code
    attr_reader :solver
    def entities; super + [@node] end
    def initialize(solver, problem_code, system_code)
      @node = NodeCode.instance
      @solver = solver
      @problem_code = problem_code
      @system_code = system_code
      @system_code.initializers << self
      super("#{@system_code.type}Solver")
    end
    def hash
      solver.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && self.solver == other.solver
    end
  end # Code
end # Solver


class Solver::Explicit < Solver
  attr_reader :evaluators
  def process!(problem, system)
    mapper.process!(problem, system)
    @evaluators = system.equations.collect {|e| [Finita::Evaluator.new(e.assignment.expression, system.type, e.merge?), e.unknown, e.domain]}
  end
  class Code < Solver::Code
    def entities; super + [@array, @mapper_code] + Code.linearize(evaluator_codes) end
    def initialize(*args)
      super
      @array = EvaluationArrayCode[@system_code.system.type]
      @mapper_code = solver.mapper.code(@problem_code, @system_code)
    end
    def evaluator_codes
      solver.evaluators.collect {|e| e.collect {|o| o.code(@problem_code)}}
    end
    def write_intf(stream)
      evaluator_codes
      stream << %$
        int #{setup}(void);
      $
    end
    def write_defs(stream)
      stream << %$
        static #{@array.type} #{evaluators};
        int #{setup}(void) {
          int index, size = #{@mapper_code.size}();
          #{@array.ctor}(&#{evaluators}, size);
          for(index = 0; index < size; ++index) {
            #{@node.type} node = #{@mapper_code.getNode}(index);
      $
      evaluator_codes.each do |evaluator, field, domain|
        merge_stmt = evaluator.merge? ? nil : 'continue;'
        stream << %$
          if(node.field == #{@mapper_code.fields.index(field)} && #{domain.within}(&#{domain.instance}, node.x, node.y, node.z)) {
            #{@array.merge}(&#{evaluators}, index, #{evaluator.instance});
            #{merge_stmt}
          }
        $
      end
      stream << %$
          }
          return FINITA_OK;
        }
        int #{@system_code.solve}(void) {
          int index, size = #{@mapper_code.size}();
          for(index = 0; index < size; ++index) {
            #{@node.type} node = #{@mapper_code.getNode}(index);
            #{@mapper_code.setValue}(index, #{@array.evaluate}(&#{evaluators}, index, node.x, node.y, node.z));
          }
          return FINITA_OK;
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
    private
    # a helper function to circumvent Array#flatten unwanted internal call to Object#to_ary; mimics Array#flatten(1)
    def self.linearize(ary)
      result = []
      ary.each do |o|
        if o.is_a?(Array)
          result.concat(o)
        else
          result << o
        end
      end
      result
    end
  end
end # Explicit


end # Finita
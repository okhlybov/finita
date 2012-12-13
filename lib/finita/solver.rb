require 'finita/common'
require 'finita/system'
require 'finita/evaluator'
require 'finita/mapper'
require 'finita/environment'


module Finita


class Solver
  include EnvironmentHandler
  attr_reader :mapper, :environment
  def initialize(mapper, environment = Environment::Sequential.new)
    @mapper = mapper
    @environment = environment
  end
  def process!(problem, system)
    setup_env(environment)
    self
  end
  def code(problem_code, system_code)
    self.class::Code.new(self, problem_code, system_code)
  end
  class Code < DataStruct::Code
    attr_reader :solver
    def entities; super + [@node, @environment_code] end
    def initialize(solver, problem_code, system_code)
      @solver = solver
      @node = NodeCode.instance
      @problem_code = problem_code
      @system_code = system_code
      @environment_code = solver.environment.code(problem_code)
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
    super
    mapper.process!(problem, system, self)
    @evaluators = system.equations.collect {|e| [Finita::Evaluator.new(e.assignment, system.type, e.merge?), e.unknown, e.domain]}
    self
  end
  class Code < Solver::Code
    def entities; super + [@entry, @array, @mapper_code] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(*args)
      super
      @entry = VectorEntryCode[@system_code.system.type]
      @array = VectorArrayCode[@system_code.system.type]
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
          int index, size = #{@mapper_code.size}(), first = #{@mapper_code.firstIndex}(), last = #{@mapper_code.lastIndex}();
          #{@array.ctor}(&#{evaluators}, size);
          for(index = first; index <= last; ++index) {
            #{@node.type} node = #{@mapper_code.getNode}(index);
      $
      evaluator_codes.each do |evaluator, field, domain|
        merge_stmt = evaluator.merge? ? nil : 'continue;'
        stream << %$
          if(node.field == #{@mapper_code.fields.index(field)} && #{domain.within}(&#{domain.instance}, node.x, node.y, node.z)) {
            #{@entry.type}* entry = #{@array.get}(&#{evaluators}, index);
            if(!entry) {
              entry = #{@entry.new}(node);
              #{@array.set}(&#{evaluators}, index, entry);
            }
            #{@entry.merge}(entry, #{evaluator.instance});
            #{merge_stmt}
          }
        $
      end
      stream << %$
          }
          return FINITA_OK;
        }
        int #{@system_code.solve}(void) {
          int index, first = #{@mapper_code.firstIndex}(), last = #{@mapper_code.lastIndex}();
      $
      unless solver.mpi?
        stream << 'FINITA_HEAD {'
      end
      stream << '#pragma omp parallel for private(index,node) kind(dynamic)' if solver.omp?
      stream << %$
        for(index = first; index <= last; ++index) {
          #{@node.type} node = #{@mapper_code.getNode}(index);
          #{@mapper_code.setValue}(index, #{@entry.evaluate}(#{@array.get}(&#{evaluators}, index)));
        }
        #{@mapper_code.synchronize}();
      $
      unless solver.mpi?
        stream << '}'
      end
      stream << %$return FINITA_OK;}$
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end
end # Explicit


class Solver::Matrix < Solver

end # Matrix



end # Finita
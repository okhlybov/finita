module Finita


class Solver::Explicit < Solver
  attr_reader :evaluators
  def process!(problem, system)
    super
    @evaluators = system.equations.collect {|e| [Finita::Evaluator.new(e.assignment, system.type), e.unknown, e.domain]}
    self
  end
  class Code < Solver::Code
    def entities; super + [@entry, @array, @mapper_code] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(*args)
      super
      @entry = VectorEntryCode[@system_code.type]
      @array = VectorArrayCode[@system_code.type]
    end
    def evaluator_codes
      @solver.evaluators.collect {|e| e.collect {|o| o.code(@problem_code)}}
    end
    def write_intf(stream)
      super
      stream << %$int #{setup}(void);$
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
        merge_stmt = evaluator.merge? ? nil : 'continue;' # TODO FIXME FIXME FIXME
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
      stream << %$}return FINITA_OK;}
        int #{@system_code.solve}(void) {
          int index, first = #{@mapper_code.firstIndex}(), last = #{@mapper_code.lastIndex}();
      $
      stream << 'FINITA_HEAD {' unless solver.mpi?
      stream << '#pragma omp parallel for private(index,node) kind(dynamic)' if solver.omp?
      stream << %$
        for(index = first; index <= last; ++index) {
          #{@node.type} node = #{@mapper_code.getNode}(index);
          #{@mapper_code.setValue}(index, #{@entry.evaluate}(#{@array.get}(&#{evaluators}, index)));
        }
        #{@mapper_code.synchronize}();
      $
      stream << '}' unless solver.mpi?
      stream << %$return FINITA_OK;}$
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end
end # Explicit


end # Finita
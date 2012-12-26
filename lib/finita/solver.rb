require 'finita/common'
require 'finita/system'
require 'finita/evaluator'
require 'finita/mapper'
require 'finita/environment'


module Finita


class Solver
  include EnvironmentHandler
  attr_reader :mapper, :environment
  def initialize(mapper, environment)
    @mapper = mapper
    @environment = environment
  end
  def process!(problem, system)
    setup_env(environment)
    mapper.process!(problem, system, self)
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
      @mapper_code = solver.mapper.code(@problem_code, @system_code)
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
    def write_intf(stream)
      stream << %$int #{@system_code.solve}(void);$
    end
  end # Code
end # Solver


class Solver::Explicit < Solver
  attr_reader :evaluators
  def process!(problem, system)
    super
    @evaluators = system.equations.collect {|e| [Finita::Evaluator.new(e.assignment, system.type, e.merge?), e.unknown, e.domain]}
    self
  end
  class Code < Solver::Code
    def entities; super + [@entry, @array, @mapper_code] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(*args)
      super
      @entry = VectorEntryCode[@system_code.system.type]
      @array = VectorArrayCode[@system_code.system.type]
    end
    def evaluator_codes
      solver.evaluators.collect {|e| e.collect {|o| o.code(@problem_code)}}
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


require 'finita/jacobian'
require 'finita/residual'
require 'finita/lhs'
require 'finita/rhs'


class Solver::Matrix < Solver
  attr_reader :jacobian
  def residual
    @residual.nil? ? @residual = Residual.new : @residual
  end
  def lhs
    @lhs.nil? ? @lhs = LHS.new : @lhs
  end
  def lhs=(lhs)
    @lhs = lhs
  end
  def rhs
    @rhs.nil? ? @rhs = RHS.new : @rhs
  end
  def rhs=(rhs)
    @rhs = rhs
  end
  def nonlinear!
    @force_nonlinear = true
  end
  def initialize(mapper, environment, jacobian, &block)
    super(mapper, environment)
    @jacobian = jacobian
    block.call(self) if block_given?
  end
  def linear?
    @linear && !@force_nonlinear
  end
  def process!(problem, system)
    super
    @linear = system.linear?
    if linear?
      lhs.process!(problem, system)
      rhs.process!(problem, system)
    else
      jacobian.process!(problem, system)
      residual.process!(problem, system)
    end
    self
  end
  class Code < Solver::Code
    def entities; super + (solver.linear? ? [@lhs_code, @rhs_code] : [@jacobian_code, @residual_code]) end
    def initialize(*args)
      super
      if solver.linear?
        @lhs_code = solver.lhs.code(@problem_code, @system_code, @mapper_code)
        @rhs_code = solver.rhs.code(@problem_code, @system_code, @mapper_code)
      else
        @jacobian_code = solver.jacobian.code(@problem_code, @system_code, @mapper_code)
        @residual_code = solver.residual.code(@problem_code, @system_code, @mapper_code)
      end
    end
    def write_initializer(stream)
      #stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$ TODO
    end
  end # Code
end # Matrix


end # Finita
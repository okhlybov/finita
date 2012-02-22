require 'set'
require 'forwardable'
require 'finita/common'
require 'finita/generator'
require 'finita/ordering'


module Finita


module SystemMixin

  TypeOrder = [Integer, Float, Complex]

  attr_reader :equations

  def initialize
    @equations = []
  end

  def unknowns
    Set.new(equations.collect {|eqn| eqn.unknown})
  end

  def type
    type = TypeOrder.first
    equations.each do |eqn|
      type = eqn.type if TypeOrder.index(type) < TypeOrder.index(eqn.type)
    end
    type
  end

end


class System

  include SystemMixin

  @@object = nil

  def self.object
    raise 'System context is not set' if @@object.nil?
    @@object
  end

  attr_reader :problem

  def name
    problem.name + @name
  end

  def solver
    @solver.nil? ? problem.solver : @solver
  end

  def solver=(solver)
    @solver = solver
  end

  def ordering
    @ordering.nil? ? problem.ordering : @ordering
  end

  def ordering=(ordering)
    @ordering = ordering
  end

  def transformer
    @t96.nil? ? problem.transformer : @t9r
  end

  def transformer=(t9r)
    @t9r = t9r
  end

  def discretizer
    @d9r.nil? ? problem.discretizer : @d9r
  end

  def discretizer=(d9r)
    @d9r = d9r
  end

  def initialize(name, problem = Finita::Problem.object, &block)
    super()
    @name = Finita.to_c(name)
    @problem = problem
    problem.systems << self
    if block_given?
      raise 'System nesting is not permitted' unless @@object.nil?
      begin
        @@object = self
        yield(self)
      ensure
        @@object = nil
      end
    end
  end

  def process
    system = AlgebraicSystem.new(self)
    equations.each do |equation|
      diffed = IncompleteDiffer.new.apply!(transformer.apply!(equation.expression))
      equation.domain.decompose.each do |domain|
        system.equations << AlgebraicEquation.new(Symbolic.simplify(RefMerger.new.apply!(discretizer.apply!(diffed, domain))), equation.unknown, domain, equation.through?, system)
      end
    end
    system
  end

end # System


class AlgebraicSystem

  class SystemCode < BoundCodeTemplate
    extend Forwardable
    def_delegators :system, :name, :unknowns, :equations
    def entities; super + [problem_code, ordering_code, NodeMapCode.instance] + evaluator_codes end
    def problem_code; gtor[system.problem] end
    def ordering_code; gtor[system.ordering] end
    def type; Generator::Scalar[system.type] end # TODO
    def write_decls(stream)
      stream << %$
        FinitaOrdering #{name}Ordering;
        void #{name}Set(#{type}, int, int, int, int);
        void #{name}SetNode(#{type}, FinitaNode);
        void #{name}SetIndex(#{type}, int);
        #{type} #{name}Get(int, int, int, int);
        #{type} #{name}GetNode(FinitaNode);
        #{type} #{name}GetIndex(int);
        void #{name}Setup();
      $
    end
    def write_defs(stream)
      #
      # *SetupOrdering()
      stream << %$
        static void #{name}SetupOrdering(FinitaOrdering* self) {
          int count = 0;
          FINITA_ASSERT(self);
      $
      unknowns.each do |u|
        stream << "count += #{gtor[u].node_count};"
      end
      stream << "FinitaOrderingCtor(self, count);"
      equations.each do |eqn|
        gtor[eqn.domain].foreach_code(stream) {
          stream << "FinitaOrderingMerge(self, FinitaNodeNew(#{unknowns.index(eqn.unknown)}, x, y, z));"
        }
      end
      stream << "#{ordering_code.freeze}(self);}"
      #
      # *Set()
      stream << %$
        void #{name}Set(#{type} value, int field, int x, int y, int z) {
          switch(field) {
      $
      unknowns.each do |u|
        stream << "case #{unknowns.index(u)} : #{u}(x,y,z) = value; break;"
      end
      stream << %$default : FINITA_FAILURE("invalid field index");$
      stream << '}}'
      #
      # *SetNode()
      stream << %$
        void #{name}SetNode(#{type} value, FinitaNode node) {
          #{name}Set(value, node.field, node.x, node.y, node.z);
        }
      $
      #
      # *SetIndex()
      stream << %$
        void #{name}SetIndex(#{type} value, int index) {
          FinitaNode node = FinitaOrderingNode(&#{name}Ordering, index);
          #{name}Set(value, node.field, node.x, node.y, node.z);
        }
      $
      #
      # *Get()
      stream << %$
        #{type} #{name}Get(int field, int x, int y, int z) {
          switch(field) {
      $
      unknowns.each do |u|
        stream << "case #{unknowns.index(u)} : return #{u}(x,y,z);"
      end
      stream << %$default : FINITA_FAILURE("invalid field index");$
      stream << '}return 0;}'
      #
      # *GetNode()
      stream << %$
        #{type} #{name}GetNode(FinitaNode node) {
          return #{name}Get(node.field, node.x, node.y, node.z);
        }
      $
      #
      # *GetIndex()
      stream << %$
        #{type} #{name}GetIndex(int index) {
          FinitaNode node = FinitaOrderingNode(&#{name}Ordering, index);
          return #{name}Get(node.field, node.x, node.y, node.z);
        }
      $
      #
      # *Setup()
      stream << "void #{name}Setup() {"
      write_setup_body(stream)
      stream << '}'
    end
    def write_setup(stream)
      stream << "#{name}Setup();"
    end
    def write_setup_body(stream)
      stream << "#{name}SetupOrdering(&#{name}Ordering);"
    end

  end # SystemCode

  class LinearSystemCode < SystemCode
    # TODO
  end # LinearSystemCode

  class NonLinearSystemCode < SystemCode
    attr_reader :evaluator
    def evaluator_codes; Set.new(evaluator.values).to_a end
    def entities; super + [FpMatrixCode.instance, FpVectorCode.instance] end
    def initialize(system, gtor)
      super({:system=>system}, gtor)
      @evaluator = {}
      equations.each {|eqn| @evaluator[eqn] = eqn.bind(gtor)}
    end
    def write_decls(stream)
      super
      stream << "FinitaFpMatrix #{name}FpMatrix; FinitaFpVector #{name}FpVector;"
    end
    def write_defs(stream)
      #
      # *SetupEvaluators()
      stream << %$
        void #{name}SetupEvaluators(FinitaFpMatrix* matrix, FinitaFpVector* vector, FinitaOrdering* ordering) {
          int index;
          FINITA_ASSERT(matrix);
          FINITA_ASSERT(vector);
          FINITA_ASSERT(ordering);
          FinitaFpMatrixCtor(matrix, FinitaOrderingSize(ordering));
          FinitaFpVectorCtor(vector, ordering);
          for(index = 0; index < ordering->linear_size; ++index) {
            int x, y, z;
            FinitaNode row = ordering->linear[index];
            x = row.x; y = row.y; z = row.z;
      $
      unknowns_list = unknowns
      unknowns_set = Set.new(unknowns_list)
      equations.each do |eqn|
        evaler = evaluator[eqn].name
        rc = RefCollector.new(unknowns_set)
        eqn.expression.apply(rc)
        stream << "if(row.field == #{unknowns_list.index(eqn.unknown)} && #{gtor[eqn.domain].within_xyz}) {"
        rc.refs.each do |ref|
          stream << "FinitaFpMatrixMerge(matrix, row, FinitaNodeNew(#{unknowns_list.index(ref.arg)}, #{ref.xindex}, #{ref.yindex}, #{ref.zindex}), (FinitaFp)#{evaler});"
        end
        stream << "FinitaFpVectorMerge(vector, index, (FinitaFp)#{evaler});"
        stream << (eqn.through? ? '}' : 'break;}')
      end
      stream << '}}'
      super
    end
    def write_setup_body(stream)
      super
      stream << "#{name}SetupEvaluators(&#{name}FpMatrix, &#{name}FpVector, &#{name}Ordering);"
    end
  end # NonLinearSystemCode

  include SystemMixin

  extend Forwardable

  def_delegators :@origin, :name, :problem, :solver, :ordering, :transformer

  def initialize(origin)
    super()
    @origin = origin
  end

  def linear?
    equations.each do |eqn|
      return false unless eqn.linear?
    end
    return true
  end

  def unknowns
    super.to_a.sort_by! {|u| u.name} # this must be a (stable) list
  end

  def bind(gtor)
    solver.bind(gtor, self)
    ordering.bind(gtor)
    transformer.bind(gtor)
    (linear? ? LinearSystemCode : NonLinearSystemCode).new(self, gtor) unless gtor.bound?(self)
    gtor.defines << :FINITA_COMPLEX if type.equal?(Complex)
  end

end # AlgebraicSystem


end # Finita
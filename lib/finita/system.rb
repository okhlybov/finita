require 'finita/common'
require 'finita/generator'
require 'finita/ordering'


module Finita


class System

  @@object = nil

  def self.object
    raise 'System context is not set' if @@object.nil?
    @@object
  end

  class Code < BoundCodeTemplate
    def entities; super + [problem_code, ordering_code, NodeMapCode.instance, FpMatrixCode.instance, FpVectorCode.instance] + evaluator_codes end
    def problem_code; gtor[master.problem] end
    def ordering_code; gtor[master.ordering] end
    def evaluator_codes
      master.algebraic_equations.collect {|eqn| gtor[eqn].evaluator}
    end
    def initialize(master, gtor)
      super
      @type = Generator::Scalar[master.type]
    end
    def write_decls(stream)
      stream << "FinitaOrdering #{master.name}Ordering; FinitaFpMatrix #{master.name}FpMatrix; FinitaFpVector #{master.name}FpVector;"
      stream << %$
        void #{master.name}Set(#{@type}, int, int, int, int);
        void #{master.name}SetNode(#{@type}, FinitaNode);
        void #{master.name}SetIndex(#{@type}, int);
        #{@type} #{master.name}Get(int, int, int, int);
        #{@type} #{master.name}GetNode(FinitaNode);
        #{@type} #{master.name}GetIndex(int);
        void #{master.name}Setup();
      $
    end
    def write_defs(stream)
      unknowns_list = Set.new(master.algebraic_equations.collect {|e| e.unknown}).to_a.sort_by! {|u| u.name} # TODO code for choosing the ordering of unknowns
      #
      # *SetupOrdering()
      stream << %$
        static void #{master.name}SetupOrdering(FinitaOrdering* self) {
          int count = 0;
          FINITA_ASSERT(self);
      $
      unknowns_list.each do |u|
        stream << "count += #{gtor[u].node_count};"
      end
      stream << "FinitaOrderingCtor(self, count);"
      master.algebraic_equations.each do |eqn|
        gtor[eqn.domain].foreach_code(stream) {
          stream << "FinitaOrderingMerge(self, FinitaNodeNew(#{unknowns_list.index(eqn.unknown)}, x, y, z));"
        }
      end
      stream << "#{ordering_code.freeze}(self);}"
      #
      # *SetupEvaluators()
      stream << %$
        static void #{master.name}SetupEvaluators(FinitaFpMatrix* matrix, FinitaFpVector* vector, FinitaOrdering* ordering) {
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
      unknowns_set = master.unknowns
      master.algebraic_equations.each do |eqn|
        evaler = gtor[eqn].evaluator.name
        rc = RefCollector.new(unknowns_set)
        eqn.lhs.apply(rc)
        stream << "if(row.field == #{unknowns_list.index(eqn.unknown)} && #{gtor[eqn.domain].within_xyz}) {"
        rc.refs.each {|ref| stream << "FinitaFpMatrixMerge(matrix, row, FinitaNodeNew(#{unknowns_list.index(ref.arg)}, #{ref.xindex}, #{ref.yindex}, #{ref.zindex}), (FinitaFp)#{evaler});"}
        stream << "FinitaFpVectorMerge(vector, index, (FinitaFp)#{evaler});"
        stream << (eqn.through? ? '}' : 'break;}')
      end
      stream << '}}'
      #
      # *Set()
      stream << %$
        void #{master.name}Set(#{@type} value, int field, int x, int y, int z) {
          switch(field) {
      $
      unknowns_list.each do |u|
        stream << "case #{unknowns_list.index(u)} : #{u}(x,y,z) = value; break;"
      end
      stream << %$default : FINITA_FAILURE("invalid field index");$
      stream << '}}'
      #
      # *SetNode()
      stream << %$
        void #{master.name}SetNode(#{@type} value, FinitaNode node) {
          #{master.name}Set(value, node.field, node.x, node.y, node.z);
        }
      $
      #
      # *SetIndex()
      stream << %$
        void #{master.name}SetIndex(#{@type} value, int index) {
          FinitaNode node = FinitaOrderingNode(&#{master.name}Ordering, index);
          #{master.name}Set(value, node.field, node.x, node.y, node.z);
        }
      $
      #
      # *Get()
      stream << %$
        #{@type} #{master.name}Get(int field, int x, int y, int z) {
          switch(field) {
      $
      unknowns_list.each do |u|
        stream << "case #{unknowns_list.index(u)} : return #{u}(x,y,z);"
      end
      stream << %$default : FINITA_FAILURE("invalid field index");$
      stream << '}return 0;}'
      #
      # *GetNode()
      stream << %$
        #{@type} #{master.name}GetNode(FinitaNode node) {
          return #{master.name}Get(node.field, node.x, node.y, node.z);
        }
      $
      #
      # *GetIndex()
      stream << %$
        #{@type} #{master.name}GetIndex(int index) {
          FinitaNode node = FinitaOrderingNode(&#{master.name}Ordering, index);
          return #{master.name}Get(node.field, node.x, node.y, node.z);
        }
      $
      #
      # *Setup()
      stream << %$
        void #{master.name}Setup() {
          #{master.name}SetupOrdering(&#{master.name}Ordering);
          #{master.name}SetupEvaluators(&#{master.name}FpMatrix, &#{master.name}FpVector, &#{master.name}Ordering);
        }
      $
    end

    def write_setup(stream)
      stream << "#{master.name}Setup();"
    end

  end # Code

  attr_reader :problem, :equations, :algebraic_equations

  def name
    problem.name + @name
  end

  def type; Float end # TODO determine actual type from the types of unknowns

  def solver
    @solver.nil? ? problem.solver : @solver
  end

  def solver=(solver)
    @solver = solver
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

  def ordering
    @ordering.nil? ? problem.ordering : @ordering
  end

  def ordering=(ordering)
    @ordering = ordering
  end

  def initialize(name, problem = Finita::Problem.object, &block)
    @name = Finita.to_c(name)
    @equations = []
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

  def process!
    @algebraic_equations = []
    equations.each do |equation|
      diffed = new_differ.apply!(transformer.apply!(equation.lhs))
      equation.domain.decompose.each do |domain|
        @algebraic_equations << AlgebraicEquation.new(Symbolic.simplify(new_ref_merger.apply!(discretizer.apply!(diffed, domain))), equation.unknown, domain, self, equation.through?)
      end
    end
  end

  def unknowns
    Set.new(algebraic_equations.collect {|eqn| eqn.unknown})
  end

  def refs
    rc = RefCollector(unknowns)
    algebraic_equations.each {|eqn| eqn.lhs.apply(rc)}
    rc.refs
  end

  def bind(gtor)
    Code.new(self, gtor) unless gtor.bound?(self)
    solver.bind(gtor, self)
    ordering.bind(gtor)
    transformer.bind(gtor)
    algebraic_equations.each {|e| e.bind(gtor)}
  end

  private

  def new_differ
    IncompleteDiffer.new
  end

  def new_ref_merger
    RefMerger.new
  end

end # System


end # Finita
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
    def entities; super + [problem_code, ordering_code, FpMatrixCode.instance, @solve] end
    def problem_code; gtor[master.problem] end
    def ordering_code; gtor[master.ordering] end
    def initialize(master, gtor)
      super
      @solve = CustomFunctionCode.new(gtor, "#{master.name}Solve", [], 'void', :write_solve)
      @type = Generator::Scalar[master.type]
    end
    def write_decls(stream)
      stream << %$
        void #{master.name}Set(#{@type}, int, int, int, int);
        void #{master.name}SetLinear(#{@type}, int);
        #{@type} #{master.name}Get(int, int, int, int);
        #{@type} #{master.name}GetLinear(int);
        void #{master.name}Setup();
      $
    end
    def write_defs(stream)
      stream << "static FinitaOrdering #{master.name}Ordering; static FinitaFpMatrix #{master.name}FpMatrix;"
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
      # *SetupMatrix()
      stream << %$
        static void #{master.name}SetupFpMatrix(FinitaFpMatrix* self, FinitaOrdering* ordering) {
          int index;
          FINITA_ASSERT(self);
          FINITA_ASSERT(ordering);
          FinitaFpMatrixCtor(self, FinitaOrderingSize(ordering));
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
        master.algebraic_equations.each do |eqn|
          stream << "if(row.field == #{unknowns_list.index(eqn.unknown)} && #{gtor[eqn.domain].within_xyz}) {"
          rc.refs.each {|ref| stream << "FinitaFpMatrixMerge(self, row, FinitaNodeNew(#{unknowns_list.index(ref.arg)}, #{ref.xindex}, #{ref.yindex}, #{ref.zindex}), (FinitaFp)#{evaler});"}
          stream << (eqn.through? ? '}' : 'break;}')
        end
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
      stream << %$
        void #{master.name}SetLinear(#{@type} value, int index) {
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
      # *GetLinear()
      stream << %$
        #{@type} #{master.name}GetLinear(int index) {
          FinitaNode node = FinitaOrderingNode(&#{master.name}Ordering, index);
          return #{master.name}Get(node.field, node.x, node.y, node.z);
        }
      $
      #
      # *Setup()
      stream << %$
        void #{master.name}Setup() {
          #{master.name}SetupOrdering(&#{master.name}Ordering);
          #{master.name}SetupFpMatrix(&#{master.name}FpMatrix, &#{master.name}Ordering);
        }
      $
    end
  end # Code

  attr_reader :problem, :equations, :algebraic_equations

  def name
    problem.name + @name
  end

  def type; Float end # TODO determine actual type from the types of unknowns

  def backend
    @backend.nil? ? problem.backend : @backend
  end

  def backend=(backend)
    @backend = backend
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
    backend.bind(gtor, self)
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
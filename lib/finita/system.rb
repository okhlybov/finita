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
    def entities; super + [problem_code, ordering_code, @solve] end
    def problem_code; gtor[master.problem] end
    def ordering_code; gtor[master.ordering] end
    def initialize(master, gtor)
      super
      @solve = CustomFunctionCode.new(gtor, "#{master.name}Solve", [], 'void', :write_solve)
      @type = Generator::Scalar[master.type]
    end
    def write_decls(stream)
      stream << %$
        extern FinitaOrdering #{master.name}Ordering;
        void #{master.name}Assemble();
        void #{master.name}Set(#{@type}, int, int, int, int);
        void #{master.name}SetLinear(#{@type}, int);
        #{@type} #{master.name}Get(int, int, int, int);
        #{@type} #{master.name}GetLinear(int);
      $
    end
    def write_defs(stream)
      uns = Set.new(master.algebraic_equations.collect {|e| e.unknown}).to_a.sort_by! {|u| u.name} # TODO code for choosing the ordering of unknowns
      # Assemble() >>>
      stream << %$
        FinitaOrdering #{master.name}GlobalOrdering;
        void #{master.name}Assemble() {
          int approx_node_count = 0;
      $
      uns.each do |u|
        stream << "approx_node_count += #{gtor[u].node_count};"
      end
      stream << "FinitaOrderingCtor(&#{master.name}GlobalOrdering, approx_node_count);"
      master.algebraic_equations.each do |eqn|
        gtor[eqn.domain].foreach_code(stream) {
          stream << %$
            FinitaNode node;
            node.field = #{uns.index(eqn.unknown)};
            node.x = x;
            node.y = y;
            node.z = z;
            FinitaOrderingPut(&#{master.name}GlobalOrdering, node);
          $
          stream << 'break;' unless eqn.through?
        }
      end
      stream << "#{ordering_code.freeze}(&#{master.name}GlobalOrdering);}"
      # <<< Assemble()
      stream << %$
        void #{master.name}Set(#{@type} value, int field, int x, int y, int z) {
          switch(field) {
      $
      uns.each do |u|
        stream << "case #{uns.index(u)} : #{u}(x,y,z) = value; break;"
      end
      stream << %$default : FINITA_FAILURE("invalid field index");$
      stream << '}}'
      stream << %$
        void #{master.name}SetLinear(#{@type} value, int index) {
          FinitaNode node = FinitaOrderingNode(&#{master.name}GlobalOrdering, index);
          #{master.name}Set(value, node.field, node.x, node.y, node.z);
        }
      $
      stream << %$
        #{@type} #{master.name}Get(int field, int x, int y, int z) {
          switch(field) {
      $
      uns.each do |u|
        stream << "case #{uns.index(u)} : return #{u}(x,y,z);"
      end
      stream << %$default : FINITA_FAILURE("invalid field index");$
      stream << '}return 0;}'
      stream << %$
        #{@type} #{master.name}GetLinear(int index) {
          FinitaNode node = FinitaOrderingNode(&#{master.name}GlobalOrdering, index);
          return #{master.name}Get(node.field, node.x, node.y, node.z);
        }
      $
    end
    def write_setup(stream)
      stream << "#{master.name}Assemble();"
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
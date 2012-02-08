require 'finita/common'
require 'finita/generator'


module Finita


class OrderingCode < StaticCodeTemplate
  TAG = :FinitaOrdering
  def entities; super + [Generator::StaticCode.instance, CoordSetCode.instance] end
  def write_intf(stream)
    stream << %$
      typedef struct {
        FinitaCoordSet coord_set;
        FinitaCoord* coord_vector;
        int coord_count;
        int frozen;
      } #{TAG};
      int #{TAG}Index(#{TAG}* self, FinitaCoord coord);
      FinitaCoord #{TAG}Coord(#{TAG}* self, int index);
      int #{TAG}Size(#{TAG}* self);
    $
  end
  def write_defs(stream)
    stream << %$
      void #{TAG}Ctor(#{TAG}* self, int coord_count) {
        FINITA_ASSERT(self);
        self->frozen = 0;
        FinitaCoordSetCtor(&self->coord_set, coord_count);
      }
      int #{TAG}Put(#{TAG}* self, FinitaCoord coord) {
        FinitaCoord* pcoord;
        FINITA_ASSERT(self);
        FINITA_ASSERT(!self->frozen);
        if(!FinitaCoordSetContains(&self->coord_set, &coord)) {
          pcoord = (FinitaCoord*) malloc(sizeof(FinitaCoord)); FINITA_ASSERT(pcoord);
          *pcoord = coord;
          FinitaCoordSetPut(&self->coord_set, pcoord);
          return 1;
        } else {
          return 0;
        }
      }
      FinitaCoord* #{TAG}Get(#{TAG}* self, FinitaCoord coord) {
        FINITA_ASSERT(self);
        return FinitaCoordSetGet(&self->coord_set, &coord);
      }
      void #{TAG}Freeze(#{TAG}* self) {
        int index = 0;
        FinitaCoordSetIt it;
        FINITA_ASSERT(self);
        FINITA_ASSERT(!self->frozen);
        self->coord_count = FinitaCoordSetSize(&self->coord_set);
        self->coord_vector = (FinitaCoord*) malloc(self->coord_count*sizeof(FinitaCoord)); FINITA_ASSERT(self->coord_vector);
        FinitaCoordSetItCtor(&it, &self->coord_set);
        while(FinitaCoordSetItHasNext(&it)) {
          FinitaCoord* pcoord = FinitaCoordSetItNext(&it);
          self->coord_vector[index] = *pcoord;
          self->coord_vector[index].index = pcoord->index = index;
          ++index;
        }
        self->frozen = 1;
      }
      int #{TAG}Index(#{TAG}* self, FinitaCoord coord) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(self->frozen);
        return FinitaCoordSetGet(&self->coord_set, &coord)->index;
      }
      FinitaCoord #{TAG}Coord(#{TAG}* self, int index) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(self->frozen);
        FINITA_ASSERT(0 <= index && index < self->coord_count);
        return self->coord_vector[index];
      }
      int #{TAG}Size(#{TAG}* self) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(self->frozen);
        return self->coord_count;
      }
    $
  end
  def source_size
    str = String.new
    write_defs(str)
    str.size
  end
end


class System

  @@object = nil

  def self.object
    raise 'System context is not set' if @@object.nil?
    @@object
  end

  class Code < BoundCodeTemplate
    def entities; super + [problem_code, OrderingCode.instance, @solve] end
    def problem_code; gtor[master.problem] end
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
      stream << %$
        FinitaOrdering #{master.name}Ordering;
        void #{master.name}Assemble() {
          FinitaCoord coord;
          int approx_node_count = 0;
      $
      uns.each do |u|
        stream << "approx_node_count += #{gtor[u].node_count};"
      end
      stream << "FinitaOrderingCtor(&#{master.name}Ordering, approx_node_count);"
      master.algebraic_equations.each do |eqn|
        gtor[eqn.domain].foreach_code(stream) {
          stream << %$
            coord.field = #{uns.index(eqn.unknown)}; /* #{eqn.unknown} */
            coord.x = x;
            coord.y = y;
            coord.z = z;
            FinitaOrderingPut(&#{master.name}Ordering, coord);
          $
        }
      end
      stream << "FinitaOrderingFreeze(&#{master.name}Ordering);}"
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
          FinitaCoord coord = FinitaOrderingCoord(&#{master.name}Ordering, index);
          #{master.name}Set(value, coord.field, coord.x, coord.y, coord.z);
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
          FinitaCoord coord = FinitaOrderingCoord(&#{master.name}Ordering, index);
          return #{master.name}Get(coord.field, coord.x, coord.y, coord.z);
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
        @algebraic_equations << AlgebraicEquation.new(Symbolic.simplify(new_ref_merger.apply!(discretizer.apply!(diffed, domain))), equation.unknown, domain, self)
      end
    end
  end

  def unknowns
    Set.new(algebraic_equations.collect {|eqn| eqn.unknown})
  end

  def bind(gtor)
    Code.new(self, gtor) unless gtor.bound?(self)
    backend.bind(gtor, self)
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
require 'set'
require 'forwardable'
require 'finita/common'
require 'finita/generator'
require 'finita/orderer'


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

  def orderer
    @orderer.nil? ? problem.orderer : @orderer
  end

  def orderer=(orderer)
    @orderer = orderer
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

  def linear=(linear)
    @want_linear = linear
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
    system = AlgebraicSystem.new(self, @want_linear)
    equations.each do |equation|
      diffed = IncompleteDiffer.new.apply!(transformer.apply!(equation.expression))
      equation.domain.decompose.each do |domain|
        system.equations << AlgebraicEquation.new(RefMerger.new.apply!(discretizer.apply!(diffed, domain)), equation.unknown, domain, equation.through?, system)
      end
    end
    system.process!
  end

end # System


class AlgebraicSystem

  class Code < BoundCodeTemplate
    extend Forwardable
    def_delegators :system, :name, :unknowns, :equations
    def entities; super + [problem_code, orderer_code] end
    def initialize(system, gtor)
      super({:system=>system}, gtor)
    end
    def problem_code; gtor[system.problem] end
    def orderer_code; gtor[system.orderer] end
    def type; Generator::Scalar[system.type] end # TODO
    def write_decls(stream)
      stream << %$
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
      # *ApproxNodeCount()
      stream << %$
        int #{name}ApproxNodeCount() {
          int count = 0;

      $
      unknowns.each do |u|
        stream << "count += #{gtor[u].node_count};"
      end
      stream << 'return count;}'
      #
      # *CollectNodes()
      stream << %$
        void #{name}CollectNodes() {
          FINITA_ASSERT(!#{name}Orderer.frozen);
      $
      equations.each do |eqn|
        gtor[eqn.domain].foreach_code(stream) {
          stream << "FinitaOrdererMerge(&#{name}Orderer, FinitaNodeNew(#{unknowns.index(eqn.unknown)}, x, y, z));"
        }
      end
      stream << '}'
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
          FinitaNode node = FinitaOrdererNode(&#{name}Orderer, index);
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
          FinitaNode node = FinitaOrdererNode(&#{name}Orderer, index);
          return #{name}Get(node.field, node.x, node.y, node.z);
        }
      $
      #
      # *Setup()
      stream << %$
        void #{name}Setup() {
          #{name}OrdererSetup();
          #{name}SolverSetup();
        }
      $
    end

    def write_setup(stream)
      stream << "#{name}Setup();"
    end

  end # SystemCode

  include SystemMixin

  extend Forwardable

  def_delegators :@origin, :name, :problem, :solver, :orderer, :transformer

  def initialize(origin, want_linear)
    super()
    @origin = origin
    @want_linear = want_linear
  end

  def linear?
    @linear
  end

  def unknowns
    super.to_a.sort_by! {|u| u.name} # this must be a (stable) list
  end

  def process!
    equations.each {|eqn| eqn.linearize!}
    really_linear = true
    equations.each do |eqn|
      unless eqn.linear?
        really_linear = false
        break
      end
    end
    @linear = if @want_linear.nil?
      really_linear
    elsif @want_linear == really_linear
      @want_linear
    else
      @want_linear ? raise('can not treat effectively non-linear system as linear') : @want_linear
    end
    equations.each {|eqn| eqn.setup!}
    self
  end

  def bind(gtor)
    solver.bind(gtor, self)
    orderer.bind(gtor, self)
    transformer.bind(gtor)
    Code.new(self, gtor)
    gtor.defines << :FINITA_COMPLEX if type.equal?(Complex)
  end

end # AlgebraicSystem


end # Finita
require "finita/common"
require "finita/system"
require "finita/evaluator"
require "finita/mapper"
require "finita/decomposer"
require "finita/environment"
require "finita/jacobian"
require "finita/residual"
require "finita/lhs"
require "finita/rhs"


module Finita


class Solver
  attr_reader :mapper
  attr_reader :decomposer
  attr_reader :environment
  def initialize(mapper, decomposer, environment, &block)
    @mapper = Finita.check_type(mapper, Mapper)
    @decomposer = Finita.check_type(decomposer, Decomposer)
    @environment = Finita.check_type(environment, Environment)
    if block_given?
      block.call(self)
    end
  end
  attr_reader :system
  def process!(system)
    @system = Finita.check_type(system, System)
    @mapper = mapper.process!(self)
    @decomposer = decomposer.process!(self)
    self
  end
  def code(system_code)
    self.class::Code.new(self, system_code)
  end
  class Code < Finita::Code
    def initialize(solver, system_code)
      @solver = Finita.check_type(solver, Solver)
      @system_code = Finita.check_type(system_code, System::Code)
      super("#{system_code.type}Solver")
      @environment_code = @solver.environment.code(system_code.problem_code) # TODO type check
      @mapper_code = Finita.check_type(@solver.mapper.code(self), Mapper::Code)
      @decomposer_code = Finita.check_type(@solver.decomposer.code(self), Decomposer::Code)
    end
    def entities
      super.concat([mapper_code, decomposer_code, @environment_code])
    end
    attr_reader :system_code
    attr_reader :mapper_code
    attr_reader :decomposer_code
    def seq?; @environment_code.seq? end
    def mpi?; @environment_code.mpi? end
    def omp?; @environment_code.omp? end
    def write_intf(stream)
      stream << %$#{extern} void #{system_code.solve}(void);$
    end
  end # Code
end # Solver


class Solver::Matrix < Solver
  attr_accessor :relative_tolerance, :absolute_tolerance, :max_steps
  def initialize(mapper, decomposer, environment, jacobian)
    super(mapper, decomposer, environment)
    @jacobian = Finita.check_type(jacobian, Jacobian)
    @residual = Residual.new
    @lhs = LHS.new
    @rhs = RHS.new
    @relative_tolerance = 1e-9
    @absolute_tolerance = 1e-10
    @max_steps = 10000
  end
  def process!(system)
    super
    @unknowns = system.unknowns.to_a
    if linear?
      @mappings = system.equations.collect do |e|
        ls = {}
        rs = {}
        e.decomposition(system.unknowns).each do |r, x|
          ls[r] = Evaluator.new(x, system.result) unless r.nil?
          rs[r] = Evaluator.new(x*r, system.result) unless r.nil? || r.xyz?
          rs[r] = Evaluator.new(x, system.result) if r.nil?
        end
        rs[nil] = Evaluator.new(0, system.result) if rs[nil].nil?
        {:lhs=>ls, :rhs=>rs, :domain=>e.domain, :unknown=>e.unknown, :merge=>e.merge?}
      end
      @lhs = lhs.process!(self)
      @rhs = rhs.process!(self)
    else
      @mappings = system.equations.collect do |e|
        js = {}
        ev = Evaluator.new(e.equation, system.result)
        ObjectCollector.new(Ref).apply!(e.equation).each do |ref|
          raise "expected reference to the Field instance (was the equation discretized?)" unless ref.arg.is_a?(Field)
          js[ref] = ev if system.unknowns.include?(ref.arg)
        end
        {:jacobian=>js, :residual=>ev, :domain=>e.domain, :unknown=>e.unknown, :merge=>e.merge?}
      end
      @jacobian = jacobian.process!(self)
      @residual = residual.process!(self)
    end
    self
  end
  def nonlinear!
    @force_nonlinear = true
  end
  def linear?
    !@force_nonlinear && system.linear?
  end
  attr_reader :unknowns
  attr_reader :mappings
  attr_reader :jacobian
  attr_reader :residual
  attr_reader :lhs
  attr_reader :rhs
  class Code < Solver::Code
    def entities
      super.concat([SparsityPatternCode, @node_set_code, jacobian_code, residual_code, lhs_code, rhs_code].compact + all_dependent_codes)
    end
    def initialize(*args)
      super
      pc = system_code.problem_code
      uns = @solver.mapper.unknowns
      @node_set_code = NodeSetCode if $debug
      @unknown_codes = @solver.unknowns.collect {|u| Finita.check_type(u.code(pc), Field::Code)}
      @evaluator_codes = []
      @domain_codes = []
      if @solver.linear?
        @mapping_codes = @solver.mappings.collect do |m|
          lcs = {}
          rcs = {}
          m[:lhs].each do |r, e|
            k = [r.xindex, r.yindex, r.zindex].collect {|index| index.to_s}.unshift(uns.index(r.arg))
            ec = Finita.check_type(e.code(pc), Evaluator::Code)
            @evaluator_codes << ec
            lcs[k] = ec
          end
          m[:rhs].each do |r, e|
            k = r.nil? ? nil : [r.xindex, r.yindex, r.zindex].collect {|index| index.to_s}.unshift(uns.index(r.arg))
            ec = Finita.check_type(e.code(pc), Evaluator::Code)
            @evaluator_codes << ec
            rcs[k] = ec
          end
          dc = m[:domain].code(pc) # TODO check type
          @domain_codes << dc
          {:lhs_codes=>lcs, :rhs_codes=>rcs, :domain_code=>dc, :unknown_index=>uns.index(m[:unknown]), :merge=>m[:merge]}
        end
        @lhs_code = @solver.lhs.code(self)
        @rhs_code = @solver.rhs.code(self)
      else
        @mapping_codes = @solver.mappings.collect do |m|
          jcs = {}
          m[:jacobian].each do |r, e|
            k = [r.xindex, r.yindex, r.zindex].collect {|index| index.to_s}.unshift(uns.index(r.arg))
            ec = Finita.check_type(e.code(pc), Evaluator::Code)
            @evaluator_codes << ec
            jcs[k] = ec
          end
          dc = m[:domain].code(pc)
          @domain_codes << dc
          rc = m[:residual].code(pc)
          @evaluator_codes << rc
          {:jacobian_codes=>jcs, :residual_code=>rc, :domain_code=>dc, :unknown_index=>uns.index(m[:unknown]), :merge=>m[:merge]}
        end
        @jacobian_code = @solver.jacobian.code(self)
        @residual_code = @solver.residual.code(self)
      end
      @all_dependent_codes = @unknown_codes + @evaluator_codes + @domain_codes
    end
    attr_reader :jacobian_code, :residual_code, :lhs_code, :rhs_code
    attr_reader :mapping_codes
    attr_reader :all_dependent_codes
    def write_defs(stream)
      super
      stream << %$static #{SparsityPatternCode.type} #{sparsity};$
      stream << %$void #{setup}(void){FINITA_ENTER;$
      write_setup_body(stream)
      stream << %${
        FILE* f = fopen("#{sparsity}.txt", "wt");
        #{SparsityPatternCode.dumpStats}(&#{sparsity}, f);
        fclose(f);
      }$ if $debug
      stream << "FINITA_LEAVE;}"
      stream << %$void #{cleanup}(void) {FINITA_ENTER;$
      write_cleanup_body(stream)
      stream << %$FINITA_LEAVE;}$
    end
    def sv_put_stmt(v)
      %$#{@node_set_code.put}(&nodes, #{v});$ if $debug
    end
    def write_setup_body(stream)
      stream << %$#{@node_set_code.type} nodes; #{@node_set_code.ctor}(&nodes);$ if $debug
      stream << %${
        int x, y, z;
        size_t index, first, last;
        FINITA_ENTER;
        first = #{decomposer_code.firstIndex}();
        last = #{decomposer_code.lastIndex}();
        #{SparsityPatternCode.ctor}(&#{sparsity});
        for(index = first; index <= last; ++index) {
          #{NodeCode.type} column, row = #{mapper_code.node}(index);
          #{sv_put_stmt("row")}
          x = row.x; y = row.y; z = row.z;
      $
      matrix_codes = @solver.linear? ? :lhs_codes : :jacobian_codes
      mapping_codes.each do |mc|
        stream << %$if(row.field == #{mc[:unknown_index]} && #{mc[:domain_code].within}(&#{mc[:domain_code].instance}, x, y, z)) {$
        mc[matrix_codes].each do |r, e|
          stream << %$
            if(#{mapper_code.hasNode}(column = #{NodeCode.new}(#{r[0]}, #{r[1]}, #{r[2]}, #{r[3]}))) {
              #{sv_put_stmt("column")}
              #{SparsityPatternCode.put}(&#{sparsity}, #{NodeCoordCode.new}(row, column));
            }
          $
        end
        stream << "continue;" unless mc[:merge]
        stream << "}"
      end
      stream << "}FINITA_LEAVE;}"
      stream << %${FINITA_ENTER;
        FILE* file = fopen("#{nodes}.txt", "wt");
        #{@node_set_code.dumpStats}(&nodes, file);
        fclose(file);
      FINITA_LEAVE;}$ if $debug
    end
    def write_clenup_body(stream) end
  end # Code
end # Matrix


end # Finita


require "finita/solver/explicit"
require "finita/solver/paralution"
require "finita/solver/viennacl"
require "finita/solver/mumps"
require "finita/solver/petsc"
require "finita/solver/lis"
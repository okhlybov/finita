require "autoc"
require "finita/evaluator"


module Finita


class RHS
  def process!(solver)
    @solver = Finita.check_type(solver, Solver::Matrix)
    self
  end
  attr_reader :solver
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < Finita::Code
    def initialize(lhs, solver_code)
      @rhs = Finita.check_type(lhs, RHS)
      @solver_code = Finita.check_type(solver_code, Solver::Matrix::Code)
      super("#{solver_code.system_code.type}RHS")
      sc = solver_code.system_code
      pc = sc.problem_code
      @vector_code = SparseVectorCode[sc.result]
      @function_list_code = FunctionListCode[sc.result]
      @mapping_codes = solver_code.mapping_codes
      sc.initializer_codes << self
    end
    def entities
      super.concat([NodeCode, NodeQueueCode, @vector_code, @function_list_code, solver_code.mapper_code, solver_code.decomposer_code] + solver_code.all_dependent_codes)
    end
    attr_reader :solver_code
    def hash
      @rhs.hash # TODO
    end
    def ==(other)
      equal?(other) || self.class == other.class && @rhs == other.instance_variable_get(:@rhs)
    end
    alias :eql? :==
    def write_intf(stream)
      stream << %$
        #{extern} void #{setup}(void);
        #{extern} #{solver_code.system_code.cresult} #{evaluate}(#{NodeCode.type});
      $
    end
    def write_defs(stream)
      mc = solver_code.mapper_code
      dc = solver_code.decomposer_code
      sc = solver_code.system_code
      stream << %$
        typedef struct {
          size_t start, stop;
          #{NodeCode.type} node;
        } #{indexS};
        static #{indexS}* #{indices};
        static #{FunctionCode[sc.result].type}* #{fps};
        static size_t #{indexCount}, #{fpCount};
        static #{@vector_code.type} #{vector};
        void #{setup}(void) {
          int x, y, z;
          size_t index, first, last;
          FINITA_ENTER;
          first = #{dc.firstIndex}();
          last = #{dc.lastIndex}();
          #{@vector_code.ctor}(&#{vector});
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} row = #{mc.node}(index);
            x = row.x; y = row.y; z = row.z;
      $
      @mapping_codes.each do |mc|
        stream << %$if(row.field == #{mc[:unknown_index]} && #{mc[:domain_code].within}(&#{mc[:domain_code].instance}, x, y, z)) {$
        stream << %$#{@vector_code.merge}(&#{vector}, row, #{mc[:rhs_codes][nil].instance});$
        mc[:rhs_codes].each do |r, ec|
          stream << %$
            if(!#{solver_code.mapper_code.hasNode}(#{NodeCode.new}(#{r.join(',')}))) {
              #{@vector_code.merge}(&#{vector}, row, #{ec.instance});
            }
          $ unless r.nil?
        end
        stream << "continue;" unless mc[:merge]
        stream << "}"
      end
      stream << '}'
      stream << 'FINITA_LEAVE;}'
      stream << %$
        #{sc.cresult} #{evaluate}(#{NodeCode.type} row) {
          #{sc.cresult} result;
          FINITA_ENTER;
          result = #{@function_list_code.summate}(#{@vector_code.get}(&#{vector}, row), row.x, row.y, row.z);
          FINITA_RETURN(result);
        }
      $
      stream << %{
        static #{NodeQueueCode.type} #{nodes};
        static void #{nodeCacheStart}() {
          #{NodeQueueCode.ctor}(&#{nodes});
        }
        static void #{nodeCache}(#{NodeCode.type} node) {
          #{NodeQueueCode.push}(&#{nodes}, node);
        }
        static void #{nodeCacheStop}() {
          #{NodeQueueCode.it} it;
          size_t i, j, start;
          #{indexCount} = #{NodeQueueCode.size}(&#{nodes}); assert(#{indexCount} > 0);
          #{indices} = (#{indexS}*)malloc(#{indexCount}*sizeof(#{indexS})); assert(#{indices});
          i = start = 0;
          #{NodeQueueCode.itCtor}(&it, &#{nodes});
          while(#{NodeQueueCode.itMove}(&it)) {
            #{indices}[i].start = start;
            #{indices}[i].node = #{NodeQueueCode.itGet}(&it);
            #{indices}[i].stop = start + #{@function_list_code.size}(#{@vector_code.get}(&#{vector}, #{indices}[i].node)) - 1;
            start = #{indices}[i].stop + 1;
            ++i;
          }
          #{fpCount} = #{indices}[#{indexCount}-1].stop + 1;
          #{fps} = (#{FunctionCode[sc.result].type}*)malloc(#{fpCount}*sizeof(#{FunctionCode[sc.result].type})); assert(#{fps});
          #{NodeQueueCode.itCtor}(&it, &#{nodes});
          i = j = 0;
          while(#{NodeQueueCode.itMove}(&it)) {
            #{@function_list_code.it} lit;
            #{@function_list_code.itCtor}(&lit, #{@vector_code.get}(&#{vector}, #{indices}[i++].node));
            while(#{@function_list_code.itMove}(&lit)) {
              #{fps}[j++] = #{@function_list_code.itGet}(&lit);
            }
          }
          #{NodeQueueCode.dtor}(&#{nodes});
        }
        // FIXME: hardcoded double
        static void #{compute}(double *values, size_t count) {
          assert(count == #{indexCount});
          #pragma omp parallel for
          for(int i = 0; i < count; ++i) {
            double v = 0;
            const int x = #{indices}[i].node.x;
            const int y = #{indices}[i].node.y;
            const int z = #{indices}[i].node.z;
            for(size_t j = #{indices}[i].start; j <= #{indices}[i].stop; ++j) v -= #{fps}[j](x, y, z);
            values[i] = v;
          }
        }
        static void #{destroy}() {
          #{@vector_code.dtor}(&#{vector});
        }
      }
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # RHS


end
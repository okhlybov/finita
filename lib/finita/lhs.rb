require "autoc"
require "finita/evaluator"


module Finita


class LHS
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
      @lhs = Finita.check_type(lhs, LHS)
      @solver_code = Finita.check_type(solver_code, Solver::Matrix::Code)
      super("#{solver_code.system_code.type}LHS")
      sc = solver_code.system_code
      @matrix_code = SparseMatrixCode[sc.result]
      @function_list_code = FunctionListCode[sc.result]
      @mapping_codes = solver_code.mapping_codes
      sc.initializer_codes << self
    end
    def entities
      super.concat([NodeCode, NodeCoordQueueCode, @matrix_code, @function_list_code, solver_code.mapper_code, solver_code.decomposer_code] + solver_code.all_dependent_codes)
    end
    attr_reader :solver_code
    def hash
      @lhs.hash # TODO
    end
    def ==(other)
      equal?(other) || self.class == other.class && @lhs == other.instance_variable_get(:@lhs)
    end
    alias :eql? :==
    def write_intf(stream)
      stream << %$
        #{extern} void #{setup}(void);
        #{extern} #{solver_code.system_code.cresult} #{evaluate}(#{NodeCode.type}, #{NodeCode.type});
      $
    end
    def write_defs(stream)
      mc = solver_code.mapper_code
      dc = solver_code.decomposer_code
      sc = solver_code.system_code
      stream << %$
        typedef struct {
          size_t start, stop;
          #{NodeCoordCode.type} coord;
          size_t row, column;
        } #{indexS};
        static #{indexS}* #{indices};
        static #{FunctionCode[sc.result].type}* #{fps};
        static size_t #{indexCount}, #{fpCount};
        static #{@matrix_code.type} #{matrix};
        void #{setup}(void) {
          int x, y, z;
          size_t index, first, last;
          FINITA_ENTER;
          first = #{dc.firstIndex}();
          last = #{dc.lastIndex}();
          #{@matrix_code.ctor}(&#{matrix});
          for(index = first; index <= last; ++index) {
            #{NodeCode.type} column, row = #{mc.node}(index);
            x = row.x; y = row.y; z = row.z;
      $
      @mapping_codes.each do |mc|
        stream << %$if(row.field == #{mc[:unknown_index]} && #{mc[:domain_code].within}(&#{mc[:domain_code].instance}, x, y, z)) {$
        mc[:lhs_codes].each do |r, ec|
          stream << %$
            if(#{solver_code.mapper_code.hasNode}(column = #{NodeCode.new}(#{r.join(',')}))) {
              #{@matrix_code.merge}(&#{matrix}, row, column, #{ec.instance});
            }
          $
        end
        stream << 'continue;' unless mc[:merge]
        stream << '}'
      end
      stream << '}'
      stream << %${
        FILE* file = fopen("#{matrix}.txt", "wt");
        #{@matrix_code.dumpStats}(&#{matrix}, file);
        fclose(file);
      }$ if $debug
      stream << "FINITA_LEAVE;}"
      abs = sc.complex? ? 'cabs' : 'abs'
      stream << %$
        #{sc.cresult} #{evaluate}(#{NodeCode.type} row, #{NodeCode.type} column) {
          #{sc.cresult} value;
          FINITA_ENTER;
          value = #{@function_list_code.summate}(#{@matrix_code.get}(&#{matrix}, #{NodeCoordCode.new}(row, column)), row.x, row.y, row.z);
          FINITA_RETURN(value);
        }
      $
      stream << %{
        static #{NodeCoordQueueCode.type} #{coords};
        static void #{coordCacheStart}() {
          #{NodeCoordQueueCode.ctor}(&#{coords});
        }
        static void #{coordCache}(#{NodeCoordCode.type} coord) {
          #{NodeCoordQueueCode.push}(&#{coords}, coord);
        }
        static void #{coordCacheStop}() {
          #{NodeCoordQueueCode.it} it;
          size_t i, j, start;
          #{indexCount} = #{NodeCoordQueueCode.size}(&#{coords}); assert(#{indexCount} > 0);
          #{indices} = malloc(#{indexCount}*sizeof(#{indexS})); assert(#{indices});
          i = start = 0;
          #{NodeCoordQueueCode.itCtor}(&it, &#{coords});
          while(#{NodeCoordQueueCode.itMove}(&it)) {
            #{indices}[i].start = start;
            #{indices}[i].coord = #{NodeCoordQueueCode.itGet}(&it);
            #{indices}[i].row = #{solver_code.mapper_code.index}(#{indices}[i].coord.row);
            #{indices}[i].column = #{solver_code.mapper_code.index}(#{indices}[i].coord.column);
            #{indices}[i].stop = start + #{@function_list_code.size}(#{@matrix_code.get}(&#{matrix}, #{indices}[i].coord)) - 1;
            start = #{indices}[i].stop + 1;
            ++i;
          }
          #{fpCount} = #{indices}[#{indexCount}-1].stop + 1;
          #{fps} = malloc(#{fpCount}*sizeof(#{FunctionCode[sc.result].type})); assert(#{fps});
          #{NodeCoordQueueCode.itCtor}(&it, &#{coords});
          i = j = 0;
          while(#{NodeCoordQueueCode.itMove}(&it)) {
            #{@function_list_code.it} lit;
            #{@function_list_code.itCtor}(&lit, #{@matrix_code.get}(&#{matrix}, #{indices}[i++].coord));
            while(#{@function_list_code.itMove}(&lit)) {
              #{fps}[j++] = #{@function_list_code.itGet}(&lit);
            }
          }
          #{NodeCoordQueueCode.dtor}(&#{coords});
        }
        // FIXME: hardcoded double
        static void #{compute}(double *values, size_t count) {
          assert(count == #{indexCount});
          #pragma parallel for
          for(size_t i = 0; i < count; ++i) {
            double v = 0;
            const int x = #{indices}[i].coord.row.x;
            const int y = #{indices}[i].coord.row.y;
            const int z = #{indices}[i].coord.row.z;
            for(size_t j = #{indices}[i].start; j <= #{indices}[i].stop; ++j) v += #{fps}[j](x, y, z);
            values[i] = v;
          }
        }
      }
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # LHS


end # Finita
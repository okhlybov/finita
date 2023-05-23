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
      super.concat([NodeCode, @matrix_code, @function_list_code, solver_code.mapper_code, solver_code.decomposer_code] + solver_code.all_dependent_codes)
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
          size_t start, count;
          #{NodeCoordCode.type} node;
          size_t i, j;
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
      stream << %{
        size_t i, start = 0;
        #{indexCount} = #{@matrix_code.size}(&#{matrix}); assert(#{indexCount} > 0);
        #{indices} = malloc(#{indexCount}*sizeof(#{indexS})); assert(#{indices});
        #{@matrix_code.it} mit;
        //
        i = 0;
        #{@matrix_code.itCtor}(&mit, &#{matrix});
        while(#{@matrix_code.itMove}(&mit)) {
          #{indices}[i].start = start;
          const #{NodeCoordCode.type} node = #{indices}[i].node = #{@matrix_code.itGetKey}(&mit);
          #{indices}[i].i = #{solver_code.mapper_code.index}(node.column);
          #{indices}[i].j = #{solver_code.mapper_code.index}(node.row);
          start += #{indices}[i].count = #{@function_list_code.size}(#{@matrix_code.itGetElement}(&mit));
          assert(#{indices}[i].count > 0);
          ++i;
        }
        //
        #{fpCount} = 0;
        for(i = 0; i < #{indexCount}; ++i) #{fpCount} += #{indices}[i].count;
        #{fps} = malloc(#{fpCount}*sizeof(#{FunctionCode[sc.result].type})); assert(#{fps});
        //
        i = 0;
        #{@matrix_code.itCtor}(&mit, &#{matrix});
        while(#{@matrix_code.itMove}(&mit)) {
          #{@function_list_code.it} lit;
          #{@function_list_code.itCtor}(&lit, #{@matrix_code.itGetElement}(&mit));
          while(#{@function_list_code.itMove}(&lit)) {
            #{fps}[i++] = #{@function_list_code.itGet}(&lit);
          }
        }
      }
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
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # LHS


end # Finita
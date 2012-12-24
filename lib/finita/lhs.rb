require 'data_struct'
require 'finita/evaluator'


module Finita


class LHS
  attr_reader :evaluators
  def code(problem_code, system_code, mapper_code)
    self.class::Code.new(self, problem_code, system_code, mapper_code)
  end
  def process!(problem, system)
    @evaluators = system.equations.collect do |e|
      hash = {}
      e.decomposition(system.unknowns).each do |r, x|
        hash[r] = Evaluator.new(x, system.type, e.merge?) unless r.nil?
      end
      [hash, e.unknown, e.domain, e.merge?]
    end
  end
  class Code < DataStruct::Code
    attr_reader :lhs
    def entities; super + [@mapper_code, @matrix, @array] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(lhs, problem_code, system_code, mapper_code)
      @lhs = lhs
      @node = NodeCode.instance
      @problem_code = problem_code
      @system_code = system_code
      @mapper_code = mapper_code
      @matrix = MatrixCode[@system_code.system.type]
      @array = MatrixArrayCode[@system_code.system.type]
      @system_code.initializers << self
      super("#{@system_code.type}LHS")
    end
    def evaluator_codes
      lhs.evaluators.collect do |e|
        result = []
        e[0].each do |r,x|
          result << x.code(@problem_code)
        end
        result << e[1].code(@problem_code) << e[2].code(@problem_code)
      end
    end
    def hash
      lhs.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && lhs == other.lhs
    end
    def write_intf(stream)
      stream << %$
        int #{setup}(void);
        #{@system_code.result} #{evaluate}(#{@node.type}, #{@node.type});
      $
    end
    def write_defs(stream)
      # TODO proper estimation of bucket size
      stream << %$
        static #{@matrix.type} #{matrix};
        static #{@array.type} #{array};
        int #{setup}(void) {
          int index, size = #{@mapper_code.size}(), first = #{@mapper_code.firstIndex}(), last = #{@mapper_code.lastIndex}();
          #{@matrix.ctor}(&#{matrix}, pow(last-first+1, 1.1));
          for(index = first; index <= last; ++index) {
            #{@node.type} row = #{@mapper_code.getNode}(index);
            int field = row.field, x = row.x, y = row.y, z = row.z;
        $
      lhs.evaluators.each do |h, f, d, m|
        field = f.code(@problem_code)
        domain = d.code(@problem_code)
        stream << %$if(field == #{@mapper_code.fields.index(field)} && #{domain.within}(&#{domain.instance}, x, y, z)) {$
        h.each do |r, e|
          evaluator = e.code(@problem_code)
          stream << %$#{@matrix.merge}(&#{matrix}, row, #{@node.new}(#{@mapper_code.mapper.fields.index(r.arg)}, #{r.xindex}, #{r.yindex}, #{r.zindex}), #{evaluator.instance});$
        end
        stream << (m ? nil : 'continue;') << '}'
      end
      abs = @system_code.system.type == Complex ? 'cabs' : 'fabs'
      stream << %$
          }
          #{@matrix.linearize}(&#{matrix}, &#{array});
          return FINITA_OK;
        }
        #{@system_code.result} #{evaluate}(#{@node.type} row, #{@node.type} column) {
          return #{@matrix.evaluate}(&#{matrix}, row, column);
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end # Code
end # LHS


end
require 'data_struct'
require 'finita/evaluator'


module Finita


class Jacobian
  def process!(problem, system) end
  def code(problem_code, system_code, mapper_code)
    self.class::Code.new(self, problem_code, system_code, mapper_code)
  end
  class Code < DataStruct::Code
    attr_reader :jacobian
    def entities; super + [@mapper_code] end
    def initialize(jacobian, problem_code, system_code, mapper_code)
      @jacobian = jacobian
      @node = NodeCode.instance
      @problem_code = problem_code
      @system_code = system_code
      @mapper_code = mapper_code
      @system_code.initializers << self
      super("#{@system_code.type}Jacobian")
    end
    def hash
      jacobian.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && jacobian == other.jacobian
    end
    def write_intf(stream)
      stream << %$#{@system_code.result} #{evaluate}(size_t);$
    end
  end # Code
end # Jacobian


class Jacobian::Numeric < Jacobian
  attr_reader :evaluators, :relative_tolerance
  def initialize(rtol)
    @relative_tolerance = rtol
  end
  def process!(problem, system)
    super
    @evaluators = system.equations.collect {|e| [Evaluator.new(e.equation, system.type), e.unknown, e.domain, e.merge?]}
  end
  class Code < Jacobian::Code
    def entities; super + [@matrix, @array] + Finita.shallow_flatten(evaluator_codes) end
    def initialize(*args)
      super
      @coord = NodeCoordCode.instance
      @matrix = MatrixCode[@system_code.system.type]
      @array = MatrixArrayCode[@system_code.system.type]
      @entry = MatrixEntryCode[@system_code.system.type]
    end
    def evaluator_codes
      jacobian.evaluators.collect {|e| e[0..-2].collect {|o| o.code(@problem_code)}}
    end
    def write_intf(stream)
      super
      stream << %$int #{setup}(void);$
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
      evaluator_codes.each do |evaluator, field, domain, merge|
        stream << %$
          if(field == #{@mapper_code.fields.index(field)} && #{domain.within}(&#{domain.instance}, x, y, z)) {
        $
        refs = ObjectCollector.new(Ref).apply!(evaluator.evaluator.expression)
        refs.keep_if {|r| @system_code.system.unknowns.include?(r.arg)}.each do |r|
          stream << %$
            #{@matrix.merge}(&#{matrix}, row, #{@node.new}(#{@mapper_code.mapper.fields.index(r.arg)}, #{r.xindex}, #{r.yindex}, #{r.zindex}), #{evaluator.instance});
          $
        end
        stream << (merge ? nil : 'continue;') << '}'
      end
      abs = @system_code.system.type == Complex ? 'cabs' : 'fabs'
      rt = jacobian.relative_tolerance
      result = @system_code.result
      stream << %$
          }
          #{@matrix.linearize}(&#{matrix}, &#{array});
          return FINITA_OK;
        }
        #{result} #{evaluate}(size_t index) {
          #{@entry.type}* entry = #{@array.get}(&#{array}, index);
          #{@node.type} column = entry->coord.column;
          #{result} result = 0, original = #{@mapper_code.nodeGet}(column);
          #{result} delta = #{abs}(original) > 100*#{rt} ? original*#{rt} : 100*pow(#{rt}, 2)*(original < 0 ? -1 : 1);
          #{@mapper_code.nodeSet}(column, original + delta);
          result += #{@entry.evaluate}(entry);
          #{@mapper_code.nodeSet}(column, original - delta);
          result -= #{@entry.evaluate}(entry);
          #{@mapper_code.nodeSet}(column, original);
          return result/(2*delta);
        }
        size_t #{size}(void) {
          return #{@array.size}(&#{array});
        }
        #{@coord.type} #{coord}(size_t index) {
          return #{@array.get}(&#{array}, index)->coord;
        }
      $
    end
    def write_initializer(stream)
      stream << %$result = #{setup}(); #{assert}(result == FINITA_OK);$
    end
  end # Code
end # Numeric


end # Finita
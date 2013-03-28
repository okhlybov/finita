require "autoc"
require "finita/symbolic"
require "finita/environment"


module Finita


class Mapper
  attr_reader :unknowns
  attr_reader :mappings
  def process!(solver)
    @solver = check_type(solver, Solver)
    @unknowns = @solver.system.unknowns.to_a # ordered list
    @mappings = @solver.system.equations.collect do |e|
      [e.domain, e.unknown]
    end
    self
  end
  def code(solver_code)
    self.class::Code.new(self, solver_code)
  end
  class Code < DataStructBuilder::Code
    def initialize(mapper, solver_code)
      @mapper = check_type(mapper, Mapper)
      @solver_code = check_type(solver_code, Solver::Code)
      super("#{solver_code.system_code.type}Mapper")
    end
    def entities
      super + [NodeCode]
    end
    attr_reader :solver_code
    def write_intf(stream)
      sc = solver_code.system_code
      stream << %$
        #{NodeCode.type} #{node}(size_t);
        int #{hasNode}(#{NodeCode.type});
        size_t #{index}(#{NodeCode.type});
        size_t #{size}(void);
        void #{indexSet}(size_t, #{sc.cresult});
        #{sc.cresult} #{indexGet}(size_t);
        void #{nodeSet}(#{NodeCode.type}, #{sc.cresult});
        #{sc.cresult} #{nodeGet}(#{NodeCode.type});
        size_t #{firstIndex}(void);
        size_t #{lastIndex}(void);
        void #{sync}(void);
      $
    end
    def write_defs(stream)
      sc = solver_code.system_code
      stream << %$
        void #{nodeSet}(#{NodeCode.type} node, #{sc.cresult} value) {
          switch(node.field) {
      $
      x = -1
      @mapper.unknowns.each do |u|
        stream << %$case #{x+=1}: #{u.name}(node.x, node.y, node.z) = value; break;$
      end
      stream << %$default: #{abort}();$
      stream << %$}}$
      stream << %$
        #{sc.cresult} #{nodeGet}(#{NodeCode.type} node) {
          switch(node.field) {
      $
      x = -1
      @mapper.unknowns.each do |u|
        stream << %$case #{x+=1}: return #{u.name}(node.x, node.y, node.z);$
      end
      stream << %$default: #{abort}();$
      stream << %$} return 0;}$
      stream << %$
        void #{indexSet}(size_t index, #{sc.cresult} value) {
          #{nodeSet}(#{node}(index), value);
        }
        #{sc.cresult} #{indexGet}(size_t index) {
          return #{nodeGet}(#{node}(index));
        }
      $
    end
    def write_initializer(stream)
      stream << %$#{setup}();$
    end
  end # Code
end # Mapper


end # Finita


require "finita/mapper/naive"
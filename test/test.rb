
require 'autoc/module'

require 'finita/cartesian'
require 'finita/matrix'
require 'finita/workload'

n3 = Finita::Cartesian::N3.instance

m = AutoC::Module.render(:_test, stateful: false) do |m|
  m << Finita::Matrix::NodeSet.new(n3.decorate(:set), n3, set_operations: false)
  m << Finita::Matrix::Matrix.new(n3.decorate(:matrix), n3)
  m << (w = Finita::Workload::Uniprocess.new(:W))
end


require 'autoc/cmake'

AutoC::CMake.render(m)

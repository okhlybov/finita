require 'autoc/module'
require 'finita/grid/cartesian'

m = AutoC::Module.render(:_finita, stateful: false) do |m|
  m << Finita::Grid::CXY
end

require 'autoc/cmake'

AutoC::CMake.render(m)

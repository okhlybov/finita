require 'autoc/module'

require 'finita/cartesian'

m = AutoC::Module.render(:_test, stateful: false) do |m|
  m << Finita::Cartesian::N3.instance.rc
end

require 'autoc/cmake'

AutoC::CMake.render(m)

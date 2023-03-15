require 'autoc/module'
require 'autoc/cstring'

m = AutoC::Module.render(:_finita) do |m|
  m << AutoC::CString.new
end

require 'autoc/cmake'

AutoC::CMake.render(m)

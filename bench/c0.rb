require 'finita/module'
require 'finita/field'
require 'finita/grid2'


N = 1024


grid = Finita::Grid2::Cartesian.new(:C2)


Finita::Module.render(:c0) do |x|
  x << grid.field(:double, type: :C2D).instance(:f).create(grid.instance(:world).create_n(N,N), 2)
  x << grid.instance(:interior).create(1,N-2,1,N-2)
  x << AutoC::Allocator::Aligning.instance
end

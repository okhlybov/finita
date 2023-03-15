require 'finita/grid'
require 'finita/grid2'
require 'finita/grid3'
require 'finita/field'
require 'finita/module'


N = 1024


grid = Finita::Grid2::Cartesian.new(:C2)


Finita::Module.render(:c0) do |x|
  x << grid.field(:double, type: :C2D).instance(:f).create(grid.instance(:world).create_n(N,N), 2)
  x << grid.instance(:interior).create(1,N-2,1,N-2)
  x << Finita::Grid::GenericMapping.new(:G3, node: Finita::Grid3::NODE)
  x << Finita::Grid3::Cartesian.new(:C3)
end
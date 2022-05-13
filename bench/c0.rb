require 'finita/module'
require 'finita/field'
require 'finita/grid2'


N = 1000


if false
  world = Finita::Grid2::Cartesian.new(:World)
  interior = Finita::Grid2::Cartesian.new(:Interior)
  Finita::Module.render(:c0) do |x|
    x << world.field(:double, type: :Field).instance(:f).create(world.instance(:world).create_n(N,N), 2)
    x << interior.instance(:interior).create(1,N-2,1,N-2)
  end
else
  world = Finita::Grid2::StaticCartesian.new(:World, N, N)
  interior = Finita::Grid2::StaticCartesian.new(:Interior, [1,N-1], [1,N-1])
  Finita::Module.render(:c0) do |x|
    x << world.field(:double, type: :Field).instance(:f).create(world.instance(:world).create, 2)
    x << interior.instance(:interior).create
  end
end
require 'finita/module'
require 'finita/field'
require 'finita/grid'


N = 10


world = Finita::Grid::Cartesian2.new(:C2)
field = world.field(:double, type: :C2F)


Finita::Module.render(:c0) do |x|
  x << field.instance(:f).create(world.instance(:world).create_n(N,N), 2)
  x << world.instance(:interior).create(1,N-2,1,N-2)
end
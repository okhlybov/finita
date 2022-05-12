
if false
require 'symbolica/core'
require 'symbolica/render'

using Symbolica::Refinements
puts Symbolica::Render::Ruby.render(2i*3-:x**-3)
end

require 'finita/field'
require 'finita/module'


g1 = Finita::Grid::Cartesian2.new(:C2)
f1 = Finita::Grid::Field.new(g1, :double, type: :C2F)

Finita::Module.render(:test) do |x|
  x << f1.instance(:F).create(g1.instance(:g1).create_n(5, 5), 2)
end

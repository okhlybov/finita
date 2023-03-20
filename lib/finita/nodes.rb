require 'autoc/record'


module Finita

  XY = AutoC::Record.new(:XY, { x: :int, y: :int }, profile: :glassbox)

  XYZ = AutoC::Record.new(:XYZ, { x: :int, y: :int, z: :int }, profile: :glassbox)

end
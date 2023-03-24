require 'autoc/record'
require 'autoc/vector'


module Finita

  XY = AutoC::Record.new(:XY, { x: :int, y: :int }, profile: :glassbox)

  VECTOR_XY = AutoC::Vector.new(:_VectorXY, XY, visibility: :internal)
  
  XYZ = AutoC::Record.new(:XYZ, { x: :int, y: :int, z: :int }, profile: :glassbox)

  VECTOR_XYZ = AutoC::Vector.new(:_VectorXYZ, XYZ, visibility: :internal)

end
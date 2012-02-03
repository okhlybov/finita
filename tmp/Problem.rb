require 'finita'
include Finita

#require 'ruby-prof'
#RubyProf.start

A = Scalar.new(:A, Integer)
B = Scalar.new(:B, Integer)

whole = Cell::Domain.new(A,B,nil)
inner = whole.interior

F = Field.new(:F, Float, whole)
G = Field.new(:G, Integer, inner)
H = Field.new(:H, Float, whole)

Problem.new(:Problem) {|p|
  p.backend = SuperLU.new
  p.transformer = CoordinateTransformer.new(Cylindrical.new, Trivial.new)
  p.discretizer = DU2.new
  System.new(:System) {|s|
    Equation.new(Nabla.new(F)+1, F, whole)
  }
}

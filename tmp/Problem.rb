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

s1=nil
p = s = nil
Problem.new(:Problem) {|p|
  p.backend = SuperLU.new
  p.transformer = CoordinateTransformer.new(Cylindrical.new, Trivial.new)
  p.discretizer = DU2.new
  s1=System.new(:System) {|s|
    Equation.new(Nabla.new(F), F, whole)
  }
}

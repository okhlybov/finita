#require 'ruby-prof'
#RubyProf.start

A = Scalar.new(:A1, Integer)
B = Scalar.new(:B1, Integer)

whole = Cubic::Domain.new(A,B,nil)
whole_area = whole.to_area
inner = whole.interior

F = Field.new(:F, Float, whole_area)
G = Field.new(:G, Float, whole)

if true
p=Problem.new(:Problem) {|p|
  p.parallel = true
  p.backend = Backend::SuperLU.new
  p.transformer = CoordinateTransform.new(Coordinate::Cylindrical.new, Transform::Trivial.new)
  p.discretizer = Discretizer::DU2.new
  p.ordering = Ordering::Naive.new
  System.new(:System) {|s|
    Equation.new(F+1, F, inner, true)
    Equation.new(G+1, G, whole, false)
  }
}
end

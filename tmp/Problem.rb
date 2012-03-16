#require 'ruby-prof'
#RubyProf.start

A = Scalar.new(:A, Integer)
B = Scalar.new(:B, Integer)

whole = Cubic::Domain.new(A,B,nil)
whole_area = whole.to_area
inner = whole.interior

F = Field.new(:F, Float, whole)
G = Field.new(:G, Float, whole)

if true
p=Problem.new(:Problem) {|p|
  p.generator = Generator::Default.new
  p.solver = Solver::Explicit.new
  p.transformer = CoordinateTransform.new(Coordinate::Cylindrical.new, Transform::Trivial.new)
  p.discretizer = Discretizer::DU2.new
  p.orderer = Orderer::Naive.new
  System.new(:System) {|s|
    Equation.new(Delta.new(Symbolic::Exp.new(F))+G, F, inner, true)
  }
}
end

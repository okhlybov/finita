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
  p.generator = Finita::Generator::Default.new {|g|
    g.environments << Environment::OpenMP.instance
  }
  p.solver = Solver::Explicit.new
  p.transformer = CoordinateTransform.new(Coordinate::Cartesian.new, Transform::Trivial.new)
  p.discretizer = Discretizer::DU2.new
  p.ordering = Ordering::Naive.new
  System.new(:System) {|s|
    Equation.new(1, F, inner, true)
    Equation.new(2, F, whole, true)
    Equation.new(7, G, whole, true)
  }
}
end

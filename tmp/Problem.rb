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
  p.solver = Solver::Matrix.new(1e-6, Evaluator::Numeric.new(1e-6), Backend::SuperLU.new)
  p.transformer = CoordinateTransform.new(Coordinate::Cylindrical.new, Transform::Trivial.new)
  p.discretizer = Discretizer::DU2.new
  p.orderer = Orderer::Naive.new
  System.new(:System) {|s|
    #Equation.new(Delta.new(Symbolic::Exp.new(F))+G, F, inner, true)
    s.linear = true
    Equation.new(F-1, F, whole, true)
    Equation.new(F-3, F, inner, true)
  }
}
end

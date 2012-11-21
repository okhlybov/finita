#require 'ruby-prof'
#RubyProf.start
include Finita

A = Scalar.new(:A, Integer)
B = Scalar.new(:B, Integer)

whole = Cubic::Domain.new(A,B,nil)
whole_area = whole.to_area
inner = whole.interior
dot = Cubic::Area.new([5,5], [5,5], nil)

F = Field.new(:F, Float, whole)
G = Field.new(:G, Float, whole)

if true
p=Problem.new(:Problem) {|p|
  p.generator = Generator::Default.new
  p.solver = Solver::Matrix.new(1e-6, Evaluator::Numeric.new(1e-6), Backend::SuperLU.new)
  #p.solver = Solver::Explicit.new
  p.transformer = CoordinateTransform.new(Coordinate::Cartesian.new, Transform::Trivial.new)
  p.discretizer = Discretizer::DU2.new
  p.mapper = Mapper::Naive.new
  System.new(:System) {|s|
    #Equation.new(Delta.new(Symbolic::Exp.new(F))+G, F, inner, true)
    s.linear = true
    Equation.new(F-1, F, whole_area.up, false)
    Equation.new(F-1, F, dot, false)
    Equation.new(Delta.new(F), F, inner, false)
    #Equation.new(F, F, whole_area, false)
    #Equation.new((F[:x+1]+F[:x-1])/2, F, inner, false)
  }
}
end

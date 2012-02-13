#require 'ruby-prof'
#RubyProf.start

A = Scalar.new(:A1, Integer)
B = Scalar.new(:B1, Integer)

whole = Cell::Domain.new(A,B,nil)
whole_area = whole.to_area
inner = whole.interior

F = Field.new(:F, Float, whole_area)
G = Field.new(:G, Float, whole)

if true
p=Problem.new(:Problem) {|p|
  p.parallel = true
  p.generator = Generator.new
  p.backend = SuperLU.new
  p.transformer = CoordinateTransformer.new(Cylindrical.new, Trivial.new)
  p.discretizer = DU2.new
  p.ordering = Ordering::Naive.new
  System.new(:System) {|s|
    Equation.new(F+1, F, inner, true)
    Equation.new(G+1, G, inner, false)
  }
}
end

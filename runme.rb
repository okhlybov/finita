#$debug = true

N = Variable.new(:N, Integer)
Z = Variable.new(:Z, Complex)
C = Constant.new(:C, 5)
A = Domain::Cubic::Area.new(N,N)
B = Domain::Cubic::Area.new([1,N-2],[1,N-2])
F = Field.new(:F, Float, A)
G = Field.new(:G, Float, A)


def laplace(f)
  (f[:x+1] + f[:x-1] + f[:y+1] + f[:y-1])/4 - f
end


Problem.new(:Problem) do |p|
  System.new(:System) do |s|
    s.discretizer = Discretizer::Trivial.new
    s.solver = Solver::MUMPS.new(Mapper::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    Equation.new(laplace(F) - G, F, B)
  end
end
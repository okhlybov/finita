#$debug = true


d3 = false


N = Variable.new(:N, Integer)
Z = Variable.new(:Z, Complex)
C = Constant.new(:C, 5)

A = d3 ? Domain::Rectangular::Domain.new(N,N,N) : Domain::Rectangular::Area.new(N,N)

F = Field.new(:F, Float, A)
G = Field.new(:G, Float, A)

if d3
  def laplace(f)
    (f[:x+1] + f[:x-1] + f[:y+1] + f[:y-1] + f[:z+1] + f[:z-1])/6 - f
  end
else
  def laplace(f)
    (f[:x+1] + f[:x-1] + f[:y+1] + f[:y-1])/4 - f
  end
end


def laplace(f)
  D.new(D.new(f,:x),:x) + D.new(D.new(f,:y),:y) + D.new(D.new(f,:z),:z)
end


Problem.new(:Problem) do
  System.new(:System) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    #env = Environment::MPI.new
    env = Environment::Sequential.new
    s.solver = Solver::LIS.new(Mapper::Naive.new, Decomposer::Naive.new, env, Jacobian::Numeric.new) do |s|
      #s.nonlinear!
    end
    Equation.new(laplace(F) - G, F, A.interior)
  end
end
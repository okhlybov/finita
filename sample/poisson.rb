# 2D Poisson problem

NX = Variable.new(:NX, Integer)
NY = Variable.new(:NY, Integer)

Whole = Domain::Rectangular::Domain.new([1,NX], [1,NY])

F = Field.new(:F, Float, Whole)

Rho = Variable.new(:Rho, Float)

def dx(f)
  D.new(f, :x)
end

def dy(f)
  D.new(f, :y)
end

def laplace(f)
  dx(dx(f)) + dy(dy(f))
end

Problem.new(:Poisson) do |p|
  System.new(:System) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::ViennaCL.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    Equation.new(laplace(F) - Rho, F, Whole.interior)
  end
end
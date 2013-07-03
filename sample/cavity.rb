NX = Variable.new(:NX, Integer)
NY = Variable.new(:NY, Integer)

A = Variable.new(:A, Float)
B = Variable.new(:B, Float)

def dx(f)
  D.new(f, :x)*A
end

def dy(f)
  D.new(f, :y)*B
end

def laplace(f)
  dx(dx(f)) + dy(dy(f))
end

Cavity = Domain::Rectangular::Domain.new(NX, NY)

T = Field.new(:T, Float, Cavity)

Problem.new(:Cavity) do |p|
  System.new(:System) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::PETSc.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new) do |s|
      #s.nonlinear!
    end
    Equation.new(T-0, T, Cavity.left)
    Equation.new(T-1, T, Cavity.right)
    Equation.new(dy(T), T, Cavity.top)
    Equation.new(dy(T), T, Cavity.bottom)
    Equation.new(laplace(T), T, Cavity.area)
  end
end
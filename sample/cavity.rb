# Buoyancy-driven convection in 2D square cavity.

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

Gr = Variable.new(:Gr, Float)
Pr = Variable.new(:Pr, Float)

Cavity = Domain::Rectangular::Domain.new(NX, NY)

T = Field.new(:T, Float, Cavity)
Psi = Field.new(:Psi, Float, Cavity)
Phi = Field.new(:Phi, Float, Cavity)

Problem.new(:Cavity) do |p|
  p << A << B << Gr << Pr << T << Psi << Phi
  System.new(:System) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::MUMPS.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    Equation.new(T-0, T, Cavity.left)
    Equation.new(T-1, T, Cavity.right)
    Equation.new(dy(T), T, Cavity.top)
    Equation.new(dy(T), T, Cavity.bottom)
    Equation.new(Phi + 2*Psi[:x+1]*A**2, Phi, Cavity.left.area)
    Equation.new(Phi + 2*Psi[:x-1]*A**2, Phi, Cavity.right.area)
    Equation.new(Phi + 2*Psi[:y-1]*B**2, Phi, Cavity.top.area)
    Equation.new(Phi + 2*Psi[:y+1]*B**2, Phi, Cavity.bottom.area)
    Equation.new(dx(T)*dy(Psi) - dy(T)*dx(Psi) - laplace(T)/Pr, T, Cavity.interior)
    Equation.new(Phi + laplace(Psi), Psi, Cavity.interior)
    Equation.new(dx(Phi)*dy(Psi) - dy(Phi)*dx(Psi) - laplace(Phi) - Gr*dx(T), Phi, Cavity.interior)
  end
end
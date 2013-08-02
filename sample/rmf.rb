NX = Variable.new(:NX, Integer)
NY = Variable.new(:NY, Integer)

A = Variable.new(:A, Float)
B = Variable.new(:B, Float)

Cylinder = Domain::Rectangular::Domain.new(NX, NY)

Tm = Variable.new(:Tm, Float) # Magnetic Taylor Number

Psi = Field.new(:Psi, Float, Cylinder)
Phi = Field.new(:Phi, Float, Cylinder)
M = Field.new(:M, Float, Cylinder)
P = Field.new(:P, Float, Cylinder)
F = Field.new(:F, Float, Cylinder)
R = Field.new(:R, Float, Cylinder)
Z = Field.new(:Z, Float, Cylinder)

def dr(f)
  D.new(f, :x)*A
end

def dz(f)
  D.new(f, :y)*B
end

def l(f)
  dr(dr(f)) + dr(f)/R + dz(dz(f))
end

def s(f)
  dr(dr(f)) - dr(f)/R + dz(dz(f))
end

def c(f)
  (dz(Psi)*(dr(f) - f/R) - dr(Psi)*dz(f))/R
end

Problem.new(:RMF) do |p|
  p << R << Z << Tm << F << P
  System.new(:Form) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::MUMPS.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    Equation.new(dr(P), P, Cylinder.right)
    Equation.new(dz(P) - R, P, Cylinder.top)
    Equation.new(dz(P) - R, P, Cylinder.bottom)
    Equation.new(l(P) - P/R**2, P, Cylinder.interior)
    Equation.new(F + dz(P) - R, F, Cylinder)
  end
end
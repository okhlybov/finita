# 2D axisymmetric fluid flow driven by the rotating magnetic field in a cylindrical cavity
#
# Reference:
# Ph. Marty, Witkowski L. et al.
# On the stability of rotating MHD flows.
# Fluid Mechanics and Its Applications Volume 51, 1999,  pp 327-343.

NX = Variable.new(:NX, Integer)
NY = Variable.new(:NY, Integer)

A = Variable.new(:A, Float) # Stretch coefficient in R-direction
B = Variable.new(:B, Float) # Stretch coefficient in Z-direction

Cylinder = Domain::Rectangular::Domain.new(NX, NY) # Cylindrical domain with 0-based indices

Tm = Variable.new(:Tm, Float) # Magnetic Taylor number

Psi = Field.new(:Psi, Float, Cylinder) # Stream function
Phi = Field.new(:Phi, Float, Cylinder) # Vorticity
M = Field.new(:M, Float, Cylinder) # Azimuthal moment
P = Field.new(:P, Float, Cylinder) # Scalar magnetic potential
F = Field.new(:F, Float, Cylinder) # Lorenz body force
R = Field.new(:R, Float, Cylinder) # R-coordinate
Z = Field.new(:Z, Float, Cylinder) # Z-coordinate

# 1st order derivative with respect to the R spatial coordinate
def dr(f)
  D.new(f, :x)*A
end

# 1st order derivative with respect to the Z spatial coordinate
def dz(f)
  D.new(f, :y)*B
end

# Laplace operator in axisymmetric cylindrical coordinate system
def l(f)
  dr(dr(f)) + dr(f)/R + dz(dz(f))
end

def s(f)
  dr(dr(f)) - dr(f)/R + dz(dz(f))
end

# Convective term in axisymmetric cylindrical coordinate system
def c(f)
  (dz(Psi)*(dr(f) - f/R) - dr(Psi)*dz(f))/R
end

Problem.new(:RMF) do |p|
  # Lorenz body force calculation
  System.new(:Force) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::LIS.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    Equation.new(dr(P), P, Cylinder.right)
    Equation.new(dz(P) - R, P, Cylinder.top)
    Equation.new(dz(P) - R, P, Cylinder.bottom)
    Equation.new(l(P) - P/R**2, P, Cylinder.interior)
    Equation.new(F + dz(P) - R, F, Cylinder)
  end
  # Flow field calculation
  System.new(:Flow) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::LIS.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    Equation.new(R*Phi - 2*Psi[:x-1]/(R-R[:x-1])**2, Phi, Cylinder.right)
    Equation.new(R*Phi - 2*Psi[:y-1]/(Z-Z[:y-1])**2, Phi, Cylinder.top)
    Equation.new(R*Phi - 2*Psi[:y+1]/(Z-Z[:y+1])**2, Phi, Cylinder.bottom)
    Equation.new(c(M) + dz(Psi)*M/R**2 - Tm**(-0.5)*s(M) - R*F, M, Cylinder.interior)
    Equation.new(s(Psi) - R*Phi, Psi, Cylinder.interior)
    Equation.new(c(Phi) - (2*M*dz(M)/R**3 - 4*M**2*dz(R)/R**4) - Tm**(-0.5)*(l(Phi) - Phi/R**2), Phi, Cylinder.interior)
  end
end
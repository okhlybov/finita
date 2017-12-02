# 2D axisymmetric fluid flow driven by the traveling magnetic field in a cylindrical cavity
# Dimensional form

NX = Variable.new(:NX, Integer)
NY = Variable.new(:NY, Integer)

DX = Variable.new(:DX, Float) # Stretch coefficient in R-direction
DY = Variable.new(:DY, Float) # Stretch coefficient in Z-direction

Cylinder = Domain::Rectangular::Domain.new(NX, NY) # Cylindrical domain with 0-based indices

Psi = Field.new(:Psi, Float, Cylinder) # Stream function
Phi = Field.new(:Phi, Float, Cylinder) # Vorticity

R = Field.new(:R, Float, Cylinder) # R-coordinate
Z = Field.new(:Z, Float, Cylinder) # Z-coordinate

Vr = Field.new(:Vr, Float, Cylinder) # Velocity in R direction
Vz = Field.new(:Vz, Float, Cylinder) # Velocity in Z direction

Hc = Variable.new(:Hc, Float) # Domain height
Rc = Variable.new(:Rc, Float) # Domain radius
Nu = Variable.new(:Nu, Float) # Kinematic viscosity of liquid
RhoM = Variable.new(:RhoM, Float) # Density of liquid
Sigma = Variable.new(:Sigma, Float) # Electric conductivity of lquid
Omega = Variable.new(:Omega, Float) # TMF frequency
B = Variable.new(:B, Float) # TMF induction
a = Variable.new(:a, Float) # Wavevector length ???

# = Variable.new(, Float)

# 1st order derivative with respect to the R spatial coordinate
def dr(f)
  D.new(f, :x)*DX
end

# 1st order derivative with respect to the Z spatial coordinate
def dz(f)
  D.new(f, :y)*DY
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
  (dz(Psi)*f/R - dz(Psi)*dr(f) + dr(Psi)*dz(f))/R
end

Problem.new(:TMFd) do |p|
  p.instances << a << Rc << Hc << R << Z << B << Sigma << Omega << RhoM
  # Flow field calculation
  System.new(:Flow) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::MUMPS.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::MPI.new, Jacobian::Numeric.new)
    Equation.new(Phi, Phi, Cylinder.left)
    Equation.new(R*Phi - 2*Psi[:x-1]/(R-R[:x-1])**2, Phi, Cylinder.right)
    Equation.new(R*Phi - 2*Psi[:y-1]/(Z-Z[:y-1])**2, Phi, Cylinder.top)
    Equation.new(R*Phi - 2*Psi[:y+1]/(Z-Z[:y+1])**2, Phi, Cylinder.bottom)
    Equation.new(c(Phi) + Nu*(l(Phi) - Phi/R**2) + UDF.new("IxaR", Float), Phi, Cylinder.interior)
    Equation.new(s(Psi) - R*Phi, Psi, Cylinder.interior)
    Equation.new(Vr, Vr, Cylinder.left)
    Equation.new(dr(Vz), Vz, Cylinder.left)
    Equation.new(R*Vr + dz(Psi), Vr, Cylinder)
    Equation.new(R*Vz - dr(Psi), Vz, Cylinder)
  end
end
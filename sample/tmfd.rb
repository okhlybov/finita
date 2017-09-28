# 2D axisymmetric fluid flow driven by the traveling magnetic field in a cylindrical cavity
# Dimensional form

NX = Variable.new(:NX, Integer)
NY = Variable.new(:NY, Integer)

DX = Variable.new(:DX, Float) # Stretch coefficient in R-direction
DY = Variable.new(:DY, Float) # Stretch coefficient in Z-direction

Cylinder = Domain::Rectangular::Domain.new(NX, NY) # Cylindrical domain with 0-based indices

Psi = Field.new(:Psi, Float, Cylinder) # Stream function
Phi = Field.new(:Phi, Float, Cylinder) # Vorticity
T = Field.new(:T, Float, Cylinder) # Temperature

R = Field.new(:R, Float, Cylinder) # R-coordinate
Z = Field.new(:Z, Float, Cylinder) # Z-coordinate

Vr = Field.new(:Vr, Float, Cylinder) # Velocity in R direction
Vz = Field.new(:Vz, Float, Cylinder) # Velocity in Z direction

Hc = Variable.new(:Hc, Float) # Domain height
Rc = Variable.new(:Rc, Float) # Domain radius
Nu = Variable.new(:Nu, Float) # Kinematic viscosity of liquid
KappaM = Variable.new(:KappaM, Float) # Heat conductivity of fluid
RhoM = Variable.new(:RhoM, Float) # Density of liquid
CpM = Variable.new(:CpM, Float) # Specific heat of liquid
Sigma = Variable.new(:Sigma, Float) # Electric conductivity of lquid
Omega = Variable.new(:Omega, Float) # TMF frequency
B = Variable.new(:B, Float) # TMF induction
a = Variable.new(:a, Float) # Wavevector length ???
BetaT = Variable.new(:BetaT, Float) # Thermal expansion coeff.
G = Variable.new(:G, Float) # Gravity coeff.

# = Variable.new(, Float)

# 1st order derivative with respect to the R spatial coordinate
def dr(f)
  D.new(f, :x)*DX
end

# 1st order derivative with respect to the Z spatial coordinate
def dz(f)
  D.new(f, :y)*DY
end

def d2r(f) dr(dr(f)) end

def d2z(f) dz(dz(f)) end

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

Problem.new(:TMFd) do |p|
  p.instances << a << Rc << Hc << R << Z << Vr << Vz << Nu << Sigma << Omega << B << RhoM << KappaM << CpM << T
  # Flow field calculation
  System.new(:Flow) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::PETSc.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    s.nonlinear!

    Equation.new(T - 1, T, Cylinder.top)
    Equation.new(T, T, Cylinder.bottom)
    Equation.new(dr(T), T, Cylinder.left)
    Equation.new(dr(T), T, Cylinder.right)
    Equation.new((dr(Psi)*dz(T) - dz(Psi)*dr(T))/(R*RhoM) - l(T)*KappaM/(RhoM*CpM), T, Cylinder.interior)

    Equation.new(s(Psi) - RhoM*R*Phi, Psi, Cylinder.interior)

    Equation.new(Phi, Phi, Cylinder.left)
    Equation.new(RhoM*R*Phi - 2*Psi[:x-1]/(R-R[:x-1])**2, Phi, Cylinder.right)
    Equation.new(RhoM*R*Phi - 2*Psi[:y-1]/(Z-Z[:y-1])**2, Phi, Cylinder.top)
    Equation.new(RhoM*R*Phi - 2*Psi[:y+1]/(Z-Z[:y+1])**2, Phi, Cylinder.bottom)
    Equation.new(c(Phi)/RhoM + Nu*(l(Phi) - Phi/R**2) - G*BetaT*dr(T) - B**2*Sigma*Omega*UDF.new("IxaR", Float) , Phi, Cylinder.interior)

    Equation.new(Vr, Vr, Cylinder.left)
    Equation.new(dr(Vz), Vz, Cylinder.left)
    Equation.new(RhoM*R*Vr + dz(Psi), Vr, Cylinder)
    Equation.new(RhoM*R*Vz - dr(Psi), Vz, Cylinder)
  end
end
# 2D axisymmetric fluid flow driven by the traveling magnetic field in a cylindrical cavity
#

NX = Variable.new(:NX, Integer)
NY = Variable.new(:NY, Integer)

A = Variable.new(:A, Float) # Stretch coefficient in R-direction
B = Variable.new(:B, Float) # Stretch coefficient in Z-direction

Cylinder = Domain::Rectangular::Domain.new(NX, NY) # Cylindrical domain with 0-based indices

Tm = Variable.new(:Tm, Float) # Magnetic Taylor number
Gr = Variable.new(:Gr, Float) # Grashof number
Pr = Variable.new(:Pr, Float) # Prandtl number
Ha = Variable.new(:Ha, Float) # Hartmann number

a = Variable.new(:a, Float) # dimentionless Wavelength

Psi = Field.new(:Psi, Float, Cylinder) # Stream function
Phi = Field.new(:Phi, Float, Cylinder) # Vorticity
T   = Field.new(:T, Float, Cylinder) # Temperature

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

I0aR = UDF.new("I0aR", Float)
I1aR = UDF.new("I1aR", Float)

Problem.new(:TMF) do |p|
  # Flow field calculation
  System.new(:Flow) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::MUMPS.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    Equation.new(R*Phi - 2*Psi[:x-1]/(R-R[:x-1])**2, Phi, Cylinder.right)
    Equation.new(R*Phi - 2*Psi[:y-1]/(Z-Z[:y-1])**2, Phi, Cylinder.top)
    Equation.new(R*Phi - 2*Psi[:y+1]/(Z-Z[:y+1])**2, Phi, Cylinder.bottom)
    Equation.new(s(Psi) - R*Phi, Psi, Cylinder.interior)
    Equation.new(c(Phi) + (l(Phi) - Phi/R**2) + (Ha*I0aR)**2*dz(dz(Psi))/R + dr((Ha**2*dr(Psi)/R - Tm/a)*I1aR**2) - Gr*dr(T), Phi, Cylinder.interior)
    Equation.new((dr(Psi)*dz(T) - dz(Psi)*dr(T))*Pr/R - l(T), T, Cylinder.interior)
  end
end
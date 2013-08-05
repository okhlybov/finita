# The equation of Bratu on 3D grid
#
# See for example:
# Janusz Karkowski. Numerical experiments with the Bratu equation in one, two and three dimensions.
# Computational and Applied Mathematics. July 2013, Volume 32, Issue 2, pp 231-244.

# Declare the grid dimensions; to be set on the C side
NX = Variable.new(:NX, Integer)
NY = Variable.new(:NY, Integer)
NZ = Variable.new(:NZ, Integer)

# Define the 3D rectangular domain; the indices are 1-based
Whole = Domain::Rectangular::Domain.new([1,NX], [1,NY], [1,NZ])

# Define the physical field which will initially be filled with zeroes during the problem setup phase
F = Field.new(:F, Float, Whole)

# Declare the problem parameter; to be set on the C side
Lambda = Variable.new(:Lambda, Float)

# Define the 1st order derivative with respect to the X spatial coordinate
def dx(f)
  D.new(f, :x)
end

# Define the 1st order derivative with respect to the Y spatial coordinate
def dy(f)
  D.new(f, :y)
end

# Define the 1st order derivative with respect to the Z spatial coordinate
def dz(f)
  D.new(f, :z)
end

# Define the Laplace operator in Cartesian space
def laplace(f)
  dx(dx(f)) + dy(dy(f)) + dz(dz(f))
end

# Define the problem
Problem.new(:Bratu) do |p|
  # Define the system
  System.new(:System) do |s|
    # Employ the finite difference discretizer for the spacial derivatives
    s.discretizer = Discretizer::FiniteDifference.new
    # Employ the PETSc sequential solver with numeric Jacobian approximation
    s.solver = Solver::PETSc.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    # The boundary conditions are obtained implicitly in form F=f, where f=0 due to zeroed field
    # Define the equation of Bratu to be solved with respect to F field on the interior nodes of the domain Whole
    Equation.new(laplace(F) + Lambda*Exp.new(F), F, Whole.interior)
  end
end
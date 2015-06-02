# Generic coordinate transformation in 2D rectangular domain defined in terms of
# user-supplied fields X(i,j) and Y(i,j) which define the mapping of curvilinear
# physical space onto the rectangular computational mesh.

require "finita/module/generic_domain"

X1 = Variable.new(:X1, Integer)
X2 = Variable.new(:X2, Integer)
Y1 = Variable.new(:Y1, Integer)
Y2 = Variable.new(:Y2, Integer)

Whole = Domain::Rectangular::Domain.new([X1,X2], [Y1,Y2])

F = Field.new(:F, Float, Whole)

Problem.new(:CtrXY) do
  Top = GenericDomainXY.new(:Top, [X1,X2], [Y1,Y2]) # This implicitly defines two fields {name}X(i,j) and {name}Y(i,j) to be set on the C side.
  System.new(:System) do |s|
    s.discretizer = Discretizer::FiniteDifference.new
    s.solver = Solver::PETSc.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new, Jacobian::Numeric.new)
    Equation.new(F - 1, F, Whole.right)
    Equation.new(Top.dn(F).top, F, Whole.top) # Zero flux b/c dF/dn == 0.
    Equation.new(Top.dn(F).bottom, F, Whole.bottom) # Zero flux b/c dF/dn == 0.
    Equation.new(Top.d2x(F) + Top.d2y(F), F, Whole.interior) # Laplace equation.
  end
end
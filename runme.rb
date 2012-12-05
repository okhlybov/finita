N = Variable.new(:N, Integer)
C = Constant.new(:C, 5)
A = Domain::Cubic::Area.new(N,N)
F = Field.new(:F, Float, A)

Problem.new(:Problem) do |p|
  System.new(:System) do |s|
    s.discretizer = Discretizer::Trivial.new
    #s.solver = Solver::Explicit.new(Mapper::Naive.new, Environment::MPI.new)
    s.solver = Solver::Explicit.new(Mapper::Naive.new)
    Assignment.new({C=>F}, A)
  end
end

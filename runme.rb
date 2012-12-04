N = Variable.new(:N, Integer)
C = Constant.new(:C, 5)
A = Domain::Cubic::Area.new(N,N,N)
B = Domain::Cubic::Area.new([1,N-1],[1,N-1],[1,N-1])
F = Field.new(:F, Float, A)

Problem.new(:Problem) do |p|
  System.new(:System) do |s|
    s.discretizer = Discretizer::Trivial.new
    s.solver = Solver::Explicit.new(Mapper::Naive.new, Environment::MPI.new)
    Assignment.new({C+N=>F}, B)
    Assignment.new({1=>F}, A)
  end
end

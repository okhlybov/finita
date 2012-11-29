N = Variable.new(:N, Integer)
C = Constant.new(:C, 5)
A = Domain::Cubic::Area.new(N,N,N)
B = Domain::Cubic::Area.new(N,N,N)
F = Field.new(:F, Float, A)

Problem.new(:Problem) do |p|
  System.new(:System) do |s|
    s.discretizer = Discretizer::Trivial.new
    s.solver = Solver::Explicit.new
    Assignment.new({C*F-1=>F}, A)
    Assignment.new({N+1=>F}, B)
  end
end

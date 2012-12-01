N = Variable.new(:N, Integer)
C = Constant.new(:C, 5)
A = Domain::Cubic::Area.new(N,N,N)
B = Domain::Cubic::Area.new(N,N,N)
F1 = Field.new(:F1, Float, A)
F2 = Field.new(:F2, Float, B)

Problem.new(:Problem) do |p|
  System.new(:System) do |s|
    s.discretizer = Discretizer::Trivial.new
    s.solver = Solver::Explicit.new(Mapper::Naive.new)
    Assignment.new({C*F2-1=>F1}, A)
    Assignment.new({N+1=>F2}, B)
  end
end

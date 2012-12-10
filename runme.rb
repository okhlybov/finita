N = Variable.new(:N, Integer)
C = Constant.new(:C, 5)
A = Domain::Cubic::Area.new(N,N)
B = Domain::Cubic::Area.new([1,N-2],[1,N-2])
F = Field.new(:F, Complex, A)

Problem.new(:Problem) do |p|
  System.new(:System) do |s|
    s.discretizer = Discretizer::Trivial.new
    s.solver = Solver::Explicit.new(Mapper::Naive.new, Environment::MPI.new)
    #s.solver = Solver::Explicit.new(Mapper::Naive.new)
    Assignment.new({(F[:x+1]-F[:x-1]+F[:y+1]-F[:y-1])/4=>F}, B)
    Assignment.new({(F[:x+1]-F[:x-1]+F[:y+1]-F[:y-1])/4=>F}, B)
    Assignment.new({N**2=>F}, B)
  end
end

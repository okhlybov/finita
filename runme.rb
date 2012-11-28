N = Variable.new(:N,Integer)
C = Constant.new(:C, 5)

Problem.new(:Problem) do |p|
  p.instances << Domain::Cubic::Area.new(N,N,N+1)
  p.instances << Domain::Cubic::Area.new(N,N,N)
  p.instances << Domain::Cubic::Area.new(N,N,N+1)
  p.instances << Field.new(:F, Float, Domain::Cubic::Area.new(N,N,N)) << Evaluator.new(2*C, Float)<< Evaluator.new(N+1, Integer)<< Evaluator.new(2*C, Float)
  System.new(:System)
end

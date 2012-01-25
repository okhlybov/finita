require 'finita'
include Finita

A = Scalar.new(:A, Integer)
B = Scalar.new(:B, Integer)

if true
whole = Cell::Domain.new(A,B,nil)
inner = whole.interior

F = Field.new(:F, Float, whole)
G = Field.new(:G, Integer, inner)

p = s = nil
Problem.new("Problem") {|p|
  p.backend = SuperLU.new
  System.new("System") {|s|
    Equation.new(F-1, F, whole)
    Equation.new(G-F, G, inner)
  }
}
end

#z=(F+G)[:x=>:x+1,:y=>11]
#im = RefMerger.new()
#z.convert.apply(im)

#puts im.result



puts Symbolic.simplify(Differ.run(G*Diff.new(F**3*G, :x)))
puts Symbolic::Add.new(:a+:a).collect.convert

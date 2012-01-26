require 'finita'
include Finita

A = Scalar.new(:A, Integer)
B = Scalar.new(:B, Integer)

if true
whole = Cell::Domain.new(A,B,nil)
inner = whole.interior

F = Field.new(:F, Float, whole)
G = Field.new(:G, Integer, inner)
H = Field.new(:H, Float, whole)

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



puts Symbolic.simplify(PartialDiffer.run(G*Diff.new(F**3*G, :x)))
puts (PartialDiffer.run(G*Diff.new(F**3*G, :x)))

puts Differ.run(Diff.new(G*Diff.new(F+G, :x), :x))

puts PartialDiffer.run(Diff.new(Diff.new(F+G, :x)*H, :x))


puts Symbolic.simplify(Differ.run(Diff.new(Symbolic::Exp.new(F), :x=>1, :y=>2)))

puts Symbolic.simplify PartialDiffer.run(Diff.new(F*G + Diff.new(H**2, :x), :x))
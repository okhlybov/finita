require "finita/common"


module Finita


class Discretizer
end # Discretizer


class Discretizer::Trivial < Discretizer
  def process!(equations)
    equations.each {|e| e.process!}
    equations
  end
end # Trivial


end # Finita
require "autoc"
require "symbolic"


module Finita


Version = "0.2"


# Simplification level
if true
  def self.expand(obj)
    Symbolic.expand(obj)
  end
  def self.simplify(obj)
    Symbolic.simplify(obj)
  end
else
  def self.expand(obj)
    Symbolic.coerce(obj).convert!.expand!
  end
  def self.simplify(obj)
    Symbolic.coerce(obj).convert!.revert!
  end
end


def self.check_type(obj, cls)
  if obj.is_a?(cls)
    obj
  else
    raise "expected an instance of class #{cls}"
  end
end


CType = {
  Integer => "int",
  Float => "double",
  Complex => "_Complex double"
}


MPIType = {
  Integer => "MPI_INT",
  Float => "MPI_DOUBLE",
  Complex => "MPI_DOUBLE" # no MPI type corrsponding to C complex therefore is has to be constructed manually from a pair of floats
}


CAbs = {
    Integer => "abs",
    Float => "fabs",
    Complex => "cabs"
}


end # Finita
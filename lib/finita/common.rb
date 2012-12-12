require 'symbolic'


module Finita


def self.expand(obj)
  Symbolic.coerce(obj).convert.expand
end

def self.simplify(obj)
  Symbolic.coerce(obj).convert.revert
end


NumericType = {
  Integer => 'int',
  Float => 'double',
  Complex => '_Complex double'
}


MPIType = {
  Integer => 'MPI_INT',
  Float => 'MPI_DOUBLE'
  # no MPI type corrsponding to C complex therefore is has to be constructed manually from a pair of floats
}


end # Finita
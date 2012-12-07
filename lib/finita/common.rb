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
  # no MPI type for complex so is has to be constructed manually form pair of doubles
}


end # Finita
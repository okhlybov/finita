require 'symbolic'


module Finita


def self.expand(obj)
  Symbolic.coerce(obj).convert.expand
end


def self.simplify(obj)
  Symbolic.coerce(obj).convert.revert
end


def self.shallow_flatten(ary)
  # a helper function to circumvent Array#flatten unwanted internal call to Object#to_ary; mimics Array#flatten(1)
  result = []
  ary.each do |o|
    if o.is_a?(Array)
      result.concat(o)
    else
      result << o
    end
  end
  result
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
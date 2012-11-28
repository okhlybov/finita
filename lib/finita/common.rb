require 'symbolic'


module Finita


def self.simplify(obj)
  Symbolic.coerce(obj).convert.revert
end


  NumericType = {
    ::Integer => 'int',
    ::Float => 'double',
    ::Complex => '_Complex double'
}


end # Finita
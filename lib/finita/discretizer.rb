require 'finita/symbolic'


module Finita


# Finite-difference second-order discretizer over the unit grid.
class DU2 < Transformer

  # TODO 2nd order mixed derivatives

  def self.D1(p, f, t)
    ->(arg, domain) do
      if domain.planes.include?(p)
        if domain.adjacent.include?(f) && domain.adjacent.include?(t)
          (arg[p+1] - arg[p-1])/2
        elsif domain.adjacent.include?(t)
          +(4*arg[p+1] - 3*arg - arg[p+2])/2
        elsif domain.adjacent.include?(f)
          -(4*arg[p-1] - 3*arg - arg[p-2])/2
        else
          raise
        end
      else
        0
      end;
    end
  end

  def self.D2(p, f, t)
    ->(arg, domain) do
      if domain.planes.include?(p)
        if domain.adjacent.include?(f) && domain.adjacent.include?(t)
          (arg[p+1] - 2*arg + arg[p-1])
        elsif domain.adjacent.include?(t)
          (arg[p+2] - 2*arg[p+1] + arg)
        elsif domain.adjacent.include?(f)
          (arg[p-2] - 2*arg[p-1] + arg)
        else
          raise
        end
      else
        0
      end;
    end
  end

  Lambda = {
    {:x=>1} => D1(:x, :left, :right),
    {:y=>1} => D1(:y, :down, :up),
    {:z=>1} => D1(:z, :back, :forth),
    {:x=>2} => D2(:x, :left, :right),
    {:y=>2} => D2(:y, :down, :up),
    {:z=>2} => D2(:z, :back, :forth)
  }

  def numeric(obj)
    @result = obj
  end

  def scalar(obj)
    @result = obj
  end

  def field(obj)
    @result = obj
  end

  def symbol(obj)
    @result = obj
  end

  def diff(obj)
    # assuming there are no other differential operators within the argument subexpression survived the derivative merge phase
    # so there is no need to recurse into the subexpression itself
    func = Lambda[obj.diffs]
    raise(ArgumentError, 'unsupported derivative') if func.nil?
    @result = func.call(obj.arg, @domain)
  end

  def apply!(obj, domain)
    adapt!(domain)
    obj.apply(self)
    result
  end

  protected

  def adapt!(domain)
    @domain = domain
    self
  end

end # DU2


end # Finita
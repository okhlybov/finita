require 'singleton'
require 'finita/common'
require 'finita/symbolic'


module Finita


class Dx < Diff
  def initialize(arg)
    super(arg, :x)
  end
  def new_instance(arg)
    Dx.new(arg)
  end
end # Dx


class Dy < Diff
  def initialize(arg)
    super(arg, :y)
  end
  def new_instance(arg)
    Dy.new(arg)
  end
end # Dy


class Dz < Diff
  def initialize(arg)
    super(arg, :z)
  end
  def new_instance(arg)
    Dz.new(arg)
  end
end # Dz


class CoordinateTransform

  def adapt!(ctr)
    self
  end

  def bind(gtor) end

end # CoordinateTransform


class Trivial < CoordinateTransform

  class Coord < Field

    include Singleton

    class Code < BoundCodeTemplate
      def write_intf(stream) stream << "\n#define #{master.name}(x,y,z) (#{master.name})\n" end
    end # Code

    def initialize(name)
      super(name, Integer, nil)
    end

    def bind(gtor)
      Code.new(self, gtor)
    end

  end # Coord

  class X < Coord
    def initialize; super(:x) end
  end # X

  class Y < Coord
    def initialize; super(:y) end
  end # Y

  class Z < Coord
    def initialize; super(:z) end
  end # Z

  def x; X.instance end

  def y; Y.instance end

  def z; Z.instance end

  def dx(obj)
    Diff.new(obj, :x)
  end

  def dy(obj)
    Diff.new(obj, :y)
  end

  def dz(obj)
    Diff.new(obj, :z)
  end

end # Trivial


class CoordinateSystem

  include Forwarder

  def adapt!(ctr)
    set_forward_obj(ctr.transform)
    self
  end

  def bind(gtor) end

end # CoordinateSystem


class Cartesian < CoordinateSystem

  def nabla(obj)
    dx(obj) + dy(obj) + dz(obj)
  end

  def delta(obj)
    dx(dx(obj)) + dy(dy(obj)) + dz(dz(obj))
  end

end # Cartesian


class Cylindrical < CoordinateSystem

  def nabla(obj)
    dx(obj) + dz(obj)/z + dy(obj)
  end

  def delta(obj)
    dx(dx(obj)) + dx(obj)/x + dy(dy(obj)) + dz(dz(obj))/x**2
  end

end # Cylindrical


class CoordinateTransformer < Transformer

  attr_reader :coords, :transform

  def initialize(coords, transform)
    @coords = coords
    @transform = transform
    coords.adapt!(self)
    transform.adapt!(self)
  end

  def bind(gtor)
    coords.bind(gtor)
    transform.bind(gtor)
  end

  def transform!(obj)
    obj.apply(self)
    result
  end

  def field(obj)
    @result = obj
  end

  def nabla(obj)
    @result = coords.nabla(recurse_arg(obj))
  end

  def delta(obj)
    @result = coords.delta(recurse_arg(obj))
  end

  private

  def recurse_arg(obj)
    obj.arg.apply(self)
    @result
  end

end # CoordinateTransformer


end # Finita
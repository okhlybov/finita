require 'singleton'
require 'finita/common'
require 'finita/symbolic'


module Finita


class CoordinateTransform < Transformer

  attr_reader :coords, :transform

  def initialize(coords, transform)
    @coords = coords
    @transform = transform
  end

  def bind(gtor)
    coords.bind(gtor)
    transform.bind(gtor)
  end

  def apply!(obj)
    coords.adapt!(self)
    transform.adapt!(self)
    obj.apply(self)
    result
  end

  # def symbol(obj) # Symbols are not allowed here

  def numeric(obj)
    @result = obj
  end

  def scalar(obj)
    @result = obj
  end

  def field(obj)
    @result = obj
  end

  def diff(obj)
    recurse_arg(obj)
    Differ.diffs_each(obj.diffs) do |diff|
      @result = case diff
      when :x
        coords.dx(@result)
      when :y
        coords.dy(@result)
      when :z
        coords.dz(@result)
      else
        raise
      end
    end
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

end # CoordinateTransform


end # Finita


module Finita::Coordinate


class CoordinateSystem

  include Finita::Forwarder

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


end # Finita::Coordinate


module Finita::Transform


class CoordinateTransform
  def adapt!(ctr)
    self
  end
end # CoordinateTransform


class Trivial < CoordinateTransform

  class Coord < Finita::Field
    include Singleton
    class Code < Finita::BoundCodeTemplate
      def write_intf(stream) stream << "\n#define #{master.name}(x,y,z) (#{master.name})\n" end
    end # Code
    def initialize(name)
      super(name, Integer, nil)
    end
    def bind(gtor)
      Code.new(self, gtor) unless gtor.bound?(self)
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

  def bind(gtor)
    [x,y,z].each {|c| c.bind(gtor)}
  end

end # Trivial


end # Finita::Transform
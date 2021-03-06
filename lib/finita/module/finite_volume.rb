require "finita"
require "delegate"


# Automatically computing mixed (1st,2nd) order approximation employing either full faces or half faces
class FiniteVolumeXY
  
  class Face
    
    Type = {
      1 => :half,
      2 => :full,
    }
    
    attr_reader :volume, :face, :quadrants, :size, :from, :to, :center
    
    def initialize(volume, face)
      @volume = volume
      @face = face
      quads = Quadrants[face]
      @quadrants = quads & volume.quadrants; raise if quadrants.size > 2
      @size = Rational(quadrants.size, 2)
      @type = Type[quadrants.size]; raise if @type.nil?
      @direction = case face when *[:e, :w] then :horizontal when *[:n, :s] then :vertical else raise end
      start, finish = quads.collect {|q| volume.quadrants & Set[q]}; raise if start.size > 1 || finish.size > 1
      @from = start.empty? ? volume.direction_center(face) : volume.quadrant_center(start.first)
      @to = finish.empty? ? volume.direction_center(face) : volume.quadrant_center(finish.first)
      @center = case @type
        when :full
          volume.direction_center(face)
        when :half
          -> f {(from.(f) + to.(f))/2}
        else
          raise
        end
    end
    
    def ds(f)
      (to.(f) - from.(f))/volume.distance(to, from)
    end
    
    def dn(f)
      (center.(f) - volume.center.(f))/volume.distance(center, volume.center)
    end
    
  end
  
  def dxdx(a, b) normal(a, b, :e, :w) end

  def dydy(a, b) normal(a, b, :n, :s) end
  
  def dxdy(a, b) tangential(a, b, :e, :w) end

  def dydx(a, b) tangential(a, b, :n, :s) end
  
  def v(a) center.(a)*size end
  
  private def normal(a, b, *faces)
    flux = 0
    f = face[faces.first]; flux += f.center.(a) * f.dn(b) * f.size unless f.nil?
    f = face[faces.last];  flux += f.center.(a) * f.dn(b) * f.size unless f.nil?
    flux
  end

  private def tangential(a, b, *faces)
    flux = 0
    f = face[faces.first]; flux += f.center.(a) * f.ds(b) * f.size unless f.nil?
    f = face[faces.last];  flux -= f.center.(a) * f.ds(b) * f.size unless f.nil?
    flux
  end

  class Node < DelegateClass(Rational)
    def initialize(base, value = 0)
      @base = base
      @value = value.to_r
      super(@value)
    end
    def is_a?(cls) @value.is_a?(cls) end
    alias :kind_of :is_a?
    def [](*args)
      args.each do |arg|
        index = Finita::Index.new(arg)
        return @value + index.delta if @base == index.base
      end
      return 0
    end
  end
  
  X = Node.new(:x)
  Y = Node.new(:y)
  
  # NOTE : we rely upon the order the quadrants are inserted into the set!
  Quadrants = {
    n: Set[:nw, :ne],
    s: Set[:sw, :se],
    e: Set[:se, :ne],
    w: Set[:sw, :nw],
  }

  InvertedQuadrants = Quadrants.invert
  
  QuadrantOffset = {
    ne: [+1,+1],
    se: [+1,-1],
    nw: [-1,+1],
    sw: [-1,-1],
  }
  
  DirectionOffset = {
    e: [+1,0],
    w: [-1,0],
    n: [0,+1],
    s: [0,-1],
  }
  
  Type = {
    1 => :quarter,
    2 => :half,
    4 => :full,
  }
  
  attr_reader :quadrants, :size, :center
  
  def initialize(*quads)
    @quadrants = Set[*(quads.empty? ? QuadrantOffset.keys : quads)]; raise unless (quadrants - QuadrantOffset.keys).empty?
    @size = Rational(quadrants.size, 4)
    @type = Type[quadrants.size]; raise if @type.nil?
    @faces = {}
    Quadrants.each do |d, qs|
      @faces[d] = Face.new(self, d) unless (quadrants & qs).empty?
    end
    @center = case @type
      when :full
        -> f {f}
      when :half
        direction_volume_center(InvertedQuadrants[quadrants])
      when :quarter
        quadrant_volume_center(quadrants.first)
      else
        raise
      end
  end
  
  def face; @faces end
  
  def quadrant_center(q)
    dx, dy = QuadrantOffset[q]
    -> f {(f + f[:x+dx] + f[:y+dy] + f[:x+dx,:y+dy])/4}
  end
  
  def quadrant_volume_center(q)
    -> f {(f + quadrant_center(q).(f))/2}
  end
  
  def direction_center(d)
    dx, dy = DirectionOffset[d]
    -> f {(f + f[:x+dx,:y+dy])/2}
  end
  
  def direction_volume_center(d)
    -> f {(f + direction_center(d).(f))/2}
  end

  def distance(p1, p2)
    result = ((p1.(X) - p2.(X))**2 + (p1.(Y) - p2.(Y))**2)**(0.5)
    raise unless result > 0
    result
  end

end


# Manually computed 1st order approximation employing half faces
class FiniteVolumeXY2
  DxDx = {
    ne: -> a,b {(3*(a + a[:x+1]) + a[:y+1] + a[:x+1,:y+1])*(3*(b[:x+1] - b) + b[:x+1,:y+1] - b[:y+1])/64},
    nw: -> a,b {-(3*(a + a[:x-1]) + a[:y+1] + a[:x-1,:y+1])*(3*(b - b[:x-1]) + b[:y+1] - b[:x-1,:y+1])/64},
    sw: -> a,b {-(3*(a + a[:x-1]) + a[:y-1] + a[:x-1,:y-1])*(3*(b - b[:x-1]) + b[:y-1] - b[:x-1,:y-1])/64},
    se: -> a,b {(3*(a + a[:x+1]) + a[:y-1] + a[:x+1,:y-1])*(3*(b[:x+1] - b) + b[:x+1,:y-1] - b[:y-1])/64},
  }
  DxDy = {
    ne: -> a,b {(3*(a + a[:x+1]) + a[:y+1] + a[:x+1,:y+1])*(b[:y+1] + b[:x+1,:y+1] - (b + b[:x+1]))/32},
    nw: -> a,b {-(3*(a + a[:x-1]) + a[:y+1] + a[:x-1,:y+1])*(b[:y+1] + b[:x-1,:y+1] - (b + b[:x-1]))/32},
    sw: -> a,b {-(3*(a + a[:x-1]) + a[:y-1] + a[:x-1,:y-1])*(b + b[:x-1] - (b[:y-1] + b[:x-1,:y-1]))/32},
    se: -> a,b {(3*(a + a[:x+1]) + a[:y-1] + a[:x+1,:y-1])*(b + b[:x+1] - (b[:y-1] + b[:x+1,:y-1]))/32},
  }
  DyDy = {
    ne: -> a,b {(3*(a + a[:y+1]) + a[:x+1] + a[:x+1,:y+1])*(3*(b[:y+1] - b) + b[:x+1,:y+1] - b[:x+1])/64},
    nw: -> a,b {(3*(a + a[:y+1]) + a[:x-1] + a[:x-1,:y+1])*(3*(b[:y+1] - b) + b[:x-1,:y+1] - b[:x-1])/64},
    sw: -> a,b {-(3*(a + a[:y-1]) + a[:x-1] + a[:x-1,:y-1])*(3*(b - b[:y-1]) + b[:x-1] - b[:x-1,:y-1])/64},
    se: -> a,b {-(3*(a + a[:y-1]) + a[:x+1] + a[:x+1,:y-1])*(3*(b - b[:y-1]) + b[:x+1] - b[:x+1,:y-1])/64},
  }
  DyDx = {
    ne: -> a,b {(3*(a + a[:y+1]) + a[:x+1] + a[:x+1,:y+1])*(b[:x+1] + b[:x+1,:y+1] - (b + b[:y+1]))/32},
    nw: -> a,b {(3*(a + a[:y+1]) + a[:x-1] + a[:x-1,:y+1])*(b + b[:y+1] - (b[:x-1] + b[:x-1,:y+1]))/32},
    sw: -> a,b {-(3*(a + a[:y-1]) + a[:x-1] + a[:x-1,:y-1])*(b + b[:y-1] - (b[:x-1] + b[:x-1,:y-1]))/32},
    se: -> a,b {-(3*(a + a[:y-1]) + a[:x+1] + a[:x+1,:y-1])*(b[:x+1] + b[:x+1,:y-1] - (b + b[:y-1]))/32},
  }
  attr_reader :quadrants
  def initialize(*quads)
    @quadrants = quads.empty? ? Set[:nw,:ne,:sw,:se] : Set[*quads]
  end
  def dxdx(a, b) merge(DxDx, a, b) end
  def dxdy(a, b) merge(DxDy, a, b) end
  def dydx(a, b) merge(DyDx, a, b) end
  def dydy(a, b) merge(DyDy, a, b) end
  def v(f) f*Rational(quadrants.size, 4) end
  private def merge(hash, a, b)
    result = 0
    hash.each {|q,code| result += code.(a,b) if quadrants.include?(q)}
    result
  end
end
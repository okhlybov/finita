require "finita"


class GenericDomainXY
  attr_reader :domain
  attr_reader :x, :y
  attr_reader :j, :g11, :g22, :g12
  def di(f) D.new(f,:x) end
  def dj(f) D.new(f,:y) end
  def initialize(name, *args)
    @domain = Domain::Rectangular::Domain.new(*args).named!(name)
    @x = Field.new("#{name}X", Float, @domain)
    @y = Field.new("#{name}Y", Float, @domain)
    @ix = Field.new("#{name}IX", Float, @domain)
    @jy = Field.new("#{name}JY", Float, @domain)
    @iy = Field.new("#{name}IY", Float, @domain)
    @jx = Field.new("#{name}JX", Float, @domain)
    @j = Field.new("#{name}J", Float, @domain)
    @g11 = Field.new("#{name}G11", Float, @domain)
    @g22 = Field.new("#{name}G22", Float, @domain)
    @g12 = Field.new("#{name}G12", Float, @domain)
    d = di(@x)*dj(@y) - di(@y)*dj(@x)
    ix = -dj(@y)/d
    jy = -di(@x)/d
    iy = +di(@y)/d
    jx = +dj(@x)/d
    System.new(name) do |s|
      s.nonlinear!
      s.discretizer = Discretizer::FiniteDifference.new
      s.solver = Solver::Explicit.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new)
      Assignment.new(ix, @ix, @domain)
      Assignment.new(jy, @jy, @domain)
      Assignment.new(iy, @iy, @domain)
      Assignment.new(jx, @jx, @domain)
      Assignment.new(d, @j, @domain)
      Assignment.new(ix**2 + jx**2, @g11, @domain)
      Assignment.new(iy**2 + jy**2, @g22, @domain)
      Assignment.new(ix*iy + jx*jy, @g12, @domain)
    end
  end
  def dn(f)
    Dn.new(self, f)
  end
  def dx(f)
    @ix*di(f) + @jx*dj(f)
  end
  def dy(f)
    @iy*di(f) + @jy*dj(f)
  end
  def d2x(f)
    di(f)*(@jx*dj(@ix) + @ix*di(@ix)) + di(di(f))*@ix**2 +
    dj(f)*(@ix*di(@jx) + @jx*dj(@jx)) + dj(dj(f))*@jx**2 +
    2*di(dj(f))*@ix*@jx
  end
  def d2y(f)
    di(f)*(@jy*dj(@iy) + @iy*di(@iy)) + di(di(f))*@iy**2 +
    dj(f)*(@iy*di(@jy) + @jy*dj(@jy)) + dj(dj(f))*@jy**2 +
    2*di(dj(f))*@iy*@jy
  end
private
  class Dn
    extend Forwardable
    def_delegators :@ctr, :x, :y, :dx, :dy
    def initialize(ctr, f) @ctr = ctr; @f = f end
    def top; -dv end
    def bottom; +dv end
    def right; -dh end
    def left; +dh end
    private
    def dv; (dy(@f) - dx(y)*dx(@f))*(1 + dx(y)**2)**(-0.5) end
    def dh; (dx(@f) - dy(x)*dy(@f))*(1 + dy(x)**2)**(-0.5) end
  end
end
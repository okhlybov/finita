require "finita"


class GenericDomainXY
  attr_reader :domain
  attr_reader :x, :y
  attr_reader :j, :g11, :g22, :g12
  def di(f) D.new(f,:x) end
  def dj(f) D.new(f,:y) end
  def initialize(name, x = :X, y = :Y, *args)
    @nx = x
    @ny = y
    @domain = Domain::Rectangular::Domain.new(*args).named!(name)
    @x = Field.new("#{name}#{@nx}", Float, domain)
    @y = Field.new("#{name}#{@ny}", Float, domain)
    @ix = Field.new("#{name}I#{@nx}", Float, domain)
    @jy = Field.new("#{name}J#{@ny}", Float, domain)
    @iy = Field.new("#{name}I#{@ny}", Float, domain)
    @jx = Field.new("#{name}J#{@nx}", Float, domain)
    @j = Field.new("#{name}J", Float, domain)
    @g11 = Field.new("#{name}G11", Float, domain)
    @g22 = Field.new("#{name}G22", Float, domain)
    @g12 = Field.new("#{name}G12", Float, domain)
    d = di(@x)*dj(@y) - di(@y)*dj(@x)
    ix = dj(@y)/d
    jy = di(@x)/d
    iy = -dj(@x)/d
    jx = -di(@y)/d
    System.new(name) do |s|
      #s.nonlinear!
      s.discretizer = Discretizer::FiniteDifference.new
      s.solver = Solver::Explicit.new(Mapper::Naive.new, Decomposer::Naive.new, Environment::Sequential.new)
      Assignment.new(ix, @ix, domain)
      Assignment.new(jy, @jy, domain)
      Assignment.new(iy, @iy, domain)
      Assignment.new(jx, @jx, domain)
      Assignment.new(d, @j, domain)
      Assignment.new(di(@x)**2 + dj(@x)**2, @g11, domain)
      Assignment.new(di(@y)**2 + dj(@y)**2, @g22, domain)
      Assignment.new(di(@x)*di(@y) + dj(@x)*dj(@y), @g12, domain)
    end
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
  Dn = Struct.new(:top, :bottom, :left, :right)
  def dn(f)
    dydx = di(y)*@ix
    h = (dy(f) - dx(y)*dx(f))*(1 + dx(y)**2)**-0.5
    dxdy = dj(x)*@jy
    v = (dx(f) - dy(x)*dy(f))*(1 + dy(x)**2)**-0.5
    Dn.new(-h, h, v, -v)
  end
end
require "symbolic"
require "finita/common"
require "finita/symbolic"


module Finita


class Discretizer; end # Discretizer


class Discretizer::Trivial < Discretizer
  def process!(equations)
    equations.each {|e| e.process!}
    equations
  end
end # Trivial


class Discretizer::FiniteDifference < Symbolic::Traverser
  def process!(equations)
    equations.collect do |equation|
      diffed = IncompleteDiffer.new.apply!(equation.expression)
      raise "discretizer requires a Rectangular::Domain domain instance" unless equation.domain.is_a?(Finita::Domain::Rectangular::Area)
      equation.domain.decompose.collect do |domain|
        @domain = domain
        diffed.apply(self) # this sets @expression
        equation.new_algebraic(Finita.simplify(Ref::Merger.new.apply!(@expression)), @domain)
      end
    end.flatten
  end
  def numeric(obj)
    @expression = obj
  end
  def constant(obj)
    @expression = obj
  end
  def variable(obj)
    @expression = obj
  end
  def field(obj)
    @expression = Ref.new(obj)
  end
  def ref(obj)
    traverse_unary(obj)
  end
  def d(obj)
    @expression = Diffs[obj.diffs].call(obj.arg, @domain)
  end
  protected
  def traverse_unary(obj)
    obj.arg.apply(self)
    @expression = obj.new_instance(@expression)
  end
  def traverse_nary(obj)
    @expression = obj.new_instance(*obj.args.collect {|arg| arg.apply(self); @expression})
  end
  def self.range(i, domain)
    case i
      when :x
        domain.xrange
      when :y
        domain.yrange
      when :z
        domain.zrange
    end
  end
  def self.d1i(f,i,d)
    r = range(i, d)
    if r.nil?
      0
    elsif r.before? && r.after?
      (f[i+1] - f[i-1])/2
    elsif r.before?
      f - f[i-1]
    elsif r.after?
      f[i+1] - f
    else
      raise
    end
  end
  def self.d2i(f,i,d)
    r = range(i, d)
    if r.nil?
      0
    elsif r.before? && r.after?
      f[i+1] - 2*f + f[i-1]
    elsif r.before?
      f - 2*f[i-1] + f[i-2]
    elsif r.after?
      f - 2*f[i+1] + f[i+2]
    else
      raise
    end
  end
    Diffs = {
      {:x=>1} => proc {|f, d| d1i(f, :x, d)},
      {:y=>1} => proc {|f, d| d1i(f, :y, d)},
      {:z=>1} => proc {|f, d| d1i(f, :z, d)},
      {:x=>2} => proc {|f, d| d2i(f, :x, d)},
      {:y=>2} => proc {|f, d| d2i(f, :y, d)},
      {:z=>2} => proc {|f, d| d2i(f, :z, d)}
    }
end


end # Finita
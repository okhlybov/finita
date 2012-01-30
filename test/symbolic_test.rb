require 'test/unit'
require 'symbolic'


class SymbolicTest < Test::Unit::TestCase

  def exp(obj)
    Symbolic::Exp.new(obj)
  end

  def log(obj)
    Symbolic::Log.new(obj)
  end

  def test_equality
    assert_equal :a, :a
    assert_not_equal :a, :b
    assert_equal 1, 1
    assert_not_equal 1, 2
    assert_equal :a+1, :a+1
    assert_equal :a+1, 1+:a
    assert_not_equal :a+1, :b+1
    assert_equal :a+:b, :b+:a
    assert_equal (:a+:b+1).convert, (1+:a+:b).convert
    assert_not_equal :a-:b, :b-:a
    assert_equal :a*:b, :a*:b
    assert_equal :a*:b, :b*:a
    assert_equal (:a*3*:b).convert, (3*:b*:a).convert
    assert_not_equal :a*:c, :b*:a
    assert_equal (:a-:b).convert, (-:b+:a).convert
    assert_not_equal (:a-:b).convert, (-:b-:a).convert
    assert_equal :a**:b, :a**:b
    assert_equal (:a*:b)**(:c*:d), (:b*:a)**(:d*:c)
    assert_equal :a**(:b+1), :a**(1+:b)
    assert_equal exp(:a*:b+2*:c**2), exp(:a*:b+(+2*:c**2))
  end

  def convert_equal(lt, rt)
    assert_equal lt.convert, rt
  end

  def convert_not_equal(lt, rt)
    assert_not_equal lt.convert, rt
  end

  def test_convert
    convert_equal 0, 0
    convert_not_equal 0, 1
    convert_equal :a, :a
    convert_not_equal :a, :b
    convert_equal :a*1, :a
    convert_equal :a*2, 2*:a
    convert_equal :a*0, 0
    convert_equal :a**0, 1
    convert_equal :a**1, :a
    convert_equal :a**(:b*0), 1
    convert_equal 0**(:a*:b+:c), 0
    convert_equal :a-:b*0, :a
    convert_equal exp(0), 1
    convert_equal log(1), 0
  end

  def diff(lt, diff, rt)
    assert_equal Symbolic::Differ.new(diff).apply(lt.convert).convert, rt.convert
  end

  def simplify_diff(lt, diff, rt)
    assert_equal Symbolic.simplify(Symbolic::Differ.new(diff).apply(lt.convert)), rt
  end

  def test_diff
    assert_equal Symbolic::Differ.new.apply((:a*:b-2*:c**2).convert), (:a*:b-2*:c**2).convert
    diff 1, :a, 0
    diff 1, {:a=>1}, 0
    diff :a, :a, 1
    diff :a, {:a=>1}, 1
    diff :a, {:a=>2}, 0
    diff :a, {:a=>1,:b=>1}, 0
    diff :a, :b, 0
    diff :a+:b, :a, 1
    diff :a+(:b-:c*3), :c, -3
    diff :c*:a+(:b-:c*3), :c, :a-3
    diff :a*:a, :a, :a+:a
    simplify_diff :a**3, :a, 3*:a**2
    simplify_diff exp(:a), :a, exp(:a)
    simplify_diff 3*exp(:a), :a, exp(:a)*3
    simplify_diff exp(:a+:b), :a, exp(:a+:b)
    simplify_diff exp(:a*:b), :a, exp(:a*:b)*:b
  end

end
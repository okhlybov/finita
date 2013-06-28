require "set"
require "autoc"
require "symbolic"
require "finita/symbolic"
require "finita/generator"


module Finita::Domain


end # Finita::Domain


module Finita::Domain::Rectangular


class Range
  def self.coerce(obj, open = false)
    if obj.nil?
      Range::Nil
    elsif obj.is_a?(Range)
      obj
    elsif obj.is_a?(Array)
      Range.new(obj.first, obj.last, open, open)
    else
      Range.new(0, Symbolic.coerce(obj)-1, open, open)
    end
  end
  attr_reader :first
  attr_reader :last
  def nil?; equal?(Nil) end
  def before?; @before end
  def after?; @after end
  def open?; before? && after? end
  def initialize(first, last, before_first = false, after_last = false)
    @first = Finita.simplify(Symbolic.coerce(first))
    @last = Finita.simplify(Symbolic.coerce(last))
    @before = before_first
    @after = after_last
  end
  def hash
    first.hash ^ last.hash # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && first == other.first && last == other.last && before? == other.before? && after? == other.after?
  end
  alias :eql? :==
  def to_a
    [first, last]
  end
  def to_s
    (before? ? "(" : "[") << Finita::Emitter.new.emit!(first) << "..." << Finita::Emitter.new.emit!(last) << (after? ? ")" : "]")
  end
  def decompose
    nil? ? [self] : [Range.new(first, first, false, true), Range.new(first+1, last-1, true, true), Range.new(last, last, true, false)]
  end
  Nil = Range.new(0,0)
end # Range


StaticCode = Class.new(DataStructBuilder::Code) do
  def write_intf(stream)
    stream << %$
      typedef struct #{type} #{type};
      typedef struct {
        int x, y, z;
      } #{node};
      struct #{type} {
        int x1, x2, y1, y2, z1, z2;
        size_t size;
        #{node}* nodes;
      };
      typedef struct #{it} #{it};
      void #{ctor}(#{type}*, int, int, int, int, int, int);
      int #{within}(#{type}*, int, int, int);
      size_t #{size}(#{type}*);
      #{inline} size_t #{index}(#{type}* self, int x, int y, int z) {
        size_t index;
        FINITA_ENTER;
        #{assert}(#{within}(self, x, y, z));
        index = (x-self->x1) + (self->y2-self->y1+1)*((y-self->y1) + (z-self->z1)*(self->x2-self->x1+1));
        FINITA_RETURN(index);
      }
      void #{itCtor}(#{it}*, #{type}*);
      int #{itHasNext}(#{it}*);
      #{node} #{itNext}(#{it}*);
    $
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(#{type}* self, int x1, int x2, int y1, int y2, int z1, int z2) {
        int i, x, y, z;
        FINITA_ENTER;
        #{assert}(self);
        #{assert}(x1 <= x2);
        #{assert}(y1 <= y2);
        #{assert}(z1 <= z2);
        self->x1 = x1;
        self->x2 = x2;
        self->y1 = y1;
        self->y2 = y2;
        self->z1 = z1;
        self->z2 = z2;
        self->size = (x2-x1+1) * (y2-y1+1) * (z2-z1+1);
        self->nodes = (#{node}*)#{malloc}(self->size*sizeof(#{node})); #{assert}(self->nodes);
        i = 0;
        for(x = self->x1; x <= self->x2; ++x)
        for(y = self->y1; y <= self->y2; ++y)
        for(z = self->z1; z <= self->z2; ++z)
        {
          #{node} node; node.x = x; node.y = y; node.z = z;
          self->nodes[i++] = node;
        }
        FINITA_LEAVE;
      }
      int #{within}(#{type}* self, int x, int y, int z) {
        int within;
        FINITA_ENTER;
        #{assert}(self);
        within = (self->x1 <= x && x <= self->x2) && (self->y1 <= y && y <= self->y2) && (self->z1 <= z && z <= self->z2);
        FINITA_RETURN(within);
      }
      size_t #{size}(#{type}* self) {
        #{assert}(self);
        return self->size;
      }
      struct #{it} {
        #{type}* area;
        size_t index;
      };
      void #{itCtor}(#{it}* self, #{type}* area) {
        FINITA_ENTER;
        #{assert}(self);
        #{assert}(area);
        self->area = area;
        self->index = 0;
        FINITA_LEAVE;
      }
      int #{itHasNext}(#{it}* self) {
        return self->index < #{size}(self->area);
      }
      #{node} #{itNext}(#{it}* self) {
        return self->area->nodes[self->index++];
      }
    $
  end
end.new("FinitaCubicArea") # StaticCode


class Area
  attr_reader :xrange, :yrange, :zrange
  attr_reader :planes
  def initialize(xs = nil, ys = nil, zs = nil)
    @xrange = Range.coerce(xs, true)
    @yrange = Range.coerce(ys, true)
    @zrange = Range.coerce(zs, true)
    @planes = Set.new
    @planes << :x unless xrange.nil?
    @planes << :y unless yrange.nil?
    @planes << :z unless zrange.nil?
  end
  def hash
    self.class.hash ^ (xrange.hash << 1) ^ (yrange.hash << 2) ^ (zrange.hash << 3) # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && xrange == other.xrange && yrange == other.yrange && zrange == other.zrange
  end
  alias :eql? :==
  def to_s
    "{" << [xrange, yrange, zrange].collect {|r| r.nil? ? "?" : r.to_s}.join(" ") << "}"
  end
  def decompose
    [self]
  end
  def code(problem_code)
    Code.new(self, problem_code)
  end
  private
  class Code < DataStructBuilder::Code
    class << self
      alias :__new__ :new
      def new(owner, problem_code)
        obj = __new__(owner, problem_code)
        problem_code << obj
      end
    end
    @@count = 0
    @@codes = {}
    attr_reader :instance
    def entities
      @entities.nil? ? @entities = super + [StaticCode] + Collector.new.apply!(*(@area.xrange.to_a + @area.yrange.to_a + @area.zrange.to_a)).instances.collect {|o| o.code(@problem_code)} : @entities
    end
    def initialize(area, problem_code)
      @area = area
      @instance = "#{StaticCode.type}#{@@count += 1}"
      @problem_code = problem_code
      super(StaticCode.type)
      problem_code.initializer_codes << self
    end
    def hash
      @area.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @area == other.instance_variable_get(:@area)
    end
    def write_intf(stream)
      stream << %$extern #{type} #{instance};$
    end
    def write_defs(stream)
      stream << %$#{type} #{instance};$
    end
    def write_initializer(stream)
      args = (@area.xrange.to_a + @area.yrange.to_a + @area.zrange.to_a).collect {|e| CEmitter.new.emit!(e)}.join(",")
      stream << %$#{ctor}(&#{instance}, #{args});$
    end
  end # Code
end # Area


class Domain < Area
  def initialize(xs = nil, ys = nil, zs = nil)
    super(Range.coerce(xs, false), Range.coerce(ys, false), Range.coerce(zs, false))
  end
  def decompose
    set = Set.new
    xrange.decompose.each do |xr|
      xopen = xr.nil? || xr.open?
      yrange.decompose.each do |yr|
        yopen = yr.nil? || yr.open?
        zrange.decompose.each do |zr|
          zopen = zr.nil? || zr.open?
          set << ((xopen && yopen && zopen) ? Area : Domain).new(xr, yr, zr)
        end
      end
    end
    set.to_a
  end
end # Domain


end # Finita::Domain
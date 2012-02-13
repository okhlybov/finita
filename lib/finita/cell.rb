require 'set'
require 'finita/common'
require 'finita/generator'


module Finita::Cell


class Area

  class StaticCode < Finita::StaticCodeTemplate
    TAG = :FinitaCell
    def entities; super + [Finita::Generator::StaticCode.instance] end
    def write_intf(stream)
      stream << %$
          typedef struct #{TAG}_ #{TAG};
          struct #{TAG}_ {
              int x1, x2, y1, y2, z1, z2;
          };
          int #{TAG}Within(#{TAG}* self, int x, int y, int z);
          void #{TAG}Ctor(#{TAG}* self, int x1, int x2, int y1, int y2, int z1, int z2);
          int #{TAG}Size(#{TAG}* self);
          int #{TAG}Encode(#{TAG}* self, int x, int y, int z);
      $
    end
    def write_defs(stream)
      stream << %$
          #define SIZE(id) (self->id##2-self->id##1+1)
          #define OFFSET(id) (id-self->id##1)
          int #{TAG}Within(#{TAG}* self, int x, int y, int z) {
              return self->x1 <= x && x <= self->x2 && self->y1 <= y && y <= self->y2 && self->z1 <= z && z <= self->z2;
          }
          void #{TAG}Ctor(#{TAG}* self, int x1, int x2, int y1, int y2, int z1, int z2) {
              FINITA_ASSERT(self->x2 >= self->x1);
              FINITA_ASSERT(self->y2 >= self->y1);
              FINITA_ASSERT(self->z2 >= self->z1);
              self->x1 = x1;
              self->x2 = x2;
              self->y1 = y1;
              self->y2 = y2;
              self->z1 = z1;
              self->z2 = z2;
          }
          int #{TAG}Size(#{TAG}* self) {
              return SIZE(x)*SIZE(y)*SIZE(z);
          }
          int #{TAG}Encode(#{TAG}* self, int x, int y, int z) {
              int index;
              FINITA_ASSERT(#{TAG}Within(self, x, y, z));
              index = OFFSET(x) + SIZE(x)*(OFFSET(y) + OFFSET(z)*SIZE(y));
              FINITA_ASSERT(0 <= index && index < #{TAG}Size(self));
              return index;
          }
          #undef SIZE
          #undef OFFSET
      $
    end
  end # StaticCode

  class Code < Finita::BoundCodeTemplate
    TAG = StaticCode::TAG
    @@index = 0
    attr_reader :index, :name
    def entities; super + [StaticCode.instance] end
    def initialize(master, gtor)
      super(master, gtor)
      @name = "#{TAG}#{@@index += 1}"
    end
    # TODO
    # As for now, Area.new(10,10,10) and Domain.new(10,10,10) will yield separate code entities, which
    # have the same contents, since the adjacency information is not captured.
    # It might be useful implement the code sharing.
    #
    def write_intf(stream)
      stream << "extern #{TAG} #{name};"
    end
    def write_defs(stream)
      stream << "#{TAG} #{name};"
    end
    def write_setup(stream)
      args = []
      [:xrange, :yrange, :zrange].each do |m|
        r = master.send(m)
        args.push(*(r.nil? ? [0,0] : [r.from, r.to]))
      end
      stream << "#{TAG}Ctor(&#{name}, #{args.join(',')});"
    end
    def write_field_intf(stream, field)
      stream << %$
        extern void* #{field.name}_;
        #define #{field.name}(x,y,z) ((#{Finita::Generator::Scalar[field.type]}*)#{field.name}_)[#{TAG}Encode(&#{name},x,y,z)]
      $
    end
    def write_field_defs(stream, field)
      stream << "void* #{field.name}_;"
    end
    def write_field_setup(stream, field)
      stream << %$
        #{field.name}_ = FINITA_MALLOC(sizeof(#{Finita::Generator::Scalar[field.type]})*#{TAG}Size(&#{name})); FINITA_ASSERT(#{field.name}_);
      $
    end
    def foreach_code(stream)
      stream << %$
        {int x, y, z;
          for(x = #{name}.x1; x <= #{name}.x2; ++x)
          for(y = #{name}.y1; y <= #{name}.y2; ++y)
          for(z = #{name}.z1; z <= #{name}.z2; ++z){
      $
      yield(self)
      stream << '}}'
    end
    def node_count
      "#{TAG}Size(&#{name})"
    end
  end # Code

  def bind(gtor)
    Code.new(self, gtor) unless gtor.bound?(self)
    ExpressionCollector.new(*([xrange,yrange,zrange].compact.collect {|r| [r.from,r.to]}.flatten)).expressions.each {|e| e.bind(gtor)}
  end

  Planes = {:x=>[:left,:right], :y=>[:up,:down], :z=>[:forth,:back]}

  attr_reader :xrange, :yrange, :zrange

  attr_reader :planes, :origin, :adjacent

  def initialize(xrange, yrange, zrange, origin = nil)
    @xrange = coerce(xrange)
    @yrange = coerce(yrange)
    @zrange = coerce(zrange)
    @origin = origin
    @planes = Set.new
    @adjacent = Set.new
    unless @xrange.nil?
      @planes << :x
      @adjacent << :left << :right
    end
    unless @yrange.nil?
      @planes << :y
      @adjacent << :up << :down
    end
    unless @zrange.nil?
      @planes << :z
      @adjacent << :forth << :back
    end
  end

  def hash
    self.class.hash ^ (xrange.hash << 1) ^ (yrange.hash << 2) ^ (zrange.hash << 3)
  end

  def ==(other)
    equal?(other) || self.class == other.class && xrange == other.xrange && yrange == other.yrange && zrange == other.zrange
  end

  alias :eql? :==

  def interior
    Area.new(xrange.nil? ? nil : xrange.sub, yrange.nil? ? nil : yrange.sub, zrange.nil? ? nil : zrange.sub, self)
  end

  def exterior
    Area.new(xrange.nil? ? nil : xrange.sup, yrange.nil? ? nil : yrange.sup, zrange.nil? ? nil : zrange.sup, self)
  end

  [:up, :down, :left, :right, :forth, :back].each do |dir|
    define_method(dir) do
      face(dir)
    end
  end

  def dimension
    count = 0
    [xrange, yrange, zrange].each {|range| count += 1 unless range.nil? || range.unit?}
    count
  end

  def to_s
    ary = []
    ary << (planes.include?(:x) ? xrange : '*')
    ary << (planes.include?(:y) ? yrange : '*')
    ary << (planes.include?(:z) ? zrange : '*')
    str = ary.join(',')
    "[#{str}]"
  end

  def decompose
    Set.new << self
  end

  private

  def range(plane)
    case plane
      when :x
        xrange
      when :y
        yrange
      when :z
        zrange
      else
        raise(ArgumentError, 'invalid plane specification')
    end
  end

  def face(direction)
    case direction
      when :left
        planes.include?(:x) ? Area.new([xrange.from, xrange.from], yrange, zrange, self) : nil
      when :right
        planes.include?(:x) ? Area.new([xrange.to, xrange.to], yrange, zrange, self) : nil
      when :up
        planes.include?(:y) ? Area.new(xrange, [yrange.to, yrange.to], zrange, self) : nil
      when :down
        planes.include?(:y) ? Area.new(xrange, [yrange.from, yrange.from], zrange, self) : nil
      when :forth
        planes.include?(:z) ? Area.new(xrange, yrange, [zrange.to, zrange.to], self) : nil
      when :back
        planes.include?(:z) ? Area.new(xrange, yrange, [zrange.from, zrange.from], self) : nil
      else
        raise(ArgumentError, 'invalid direction specification')
    end
  end

  def coerce(obj)
    if obj.nil?
      nil
    elsif obj.is_a?(Finita::Range)
      obj
    elsif obj.is_a?(Array)
      Finita::Range.new(*obj)
    else
      Finita::Range.new(obj)
    end
  end

end # Area


class Domain < Area

  def initialize(xrange, yrange, zrange, adjacent = nil, origin = nil)
    super(xrange, yrange, zrange, origin)
    @adjacent = adjacent unless adjacent.nil?
  end

  def hash
    super ^ (adjacent.hash << 1)
  end

  def ==(other)
    super && adjacent == other.adjacent
  end

  alias :eql? :==

  [:up, :down, :left, :right, :forth, :back].each do |dir|
    define_method(dir) do
      area = face(dir)
      Domain.new(area.xrange, area.yrange, area.zrange, adjacent - [dir], self)
    end
  end

  def to_s
    super + "{#{adjacent.to_a.join(',')}}"
  end

  def to_area
    Area.new(xrange, yrange, zrange, self)
  end

  def decompose
    area = interior
    set = Set.new << Domain.new(area.xrange, area.yrange, area.zrange, adjacent, self)
    Planes.each do |p, d|
      r = range(p)
      unless r.nil? || r.unit?
        d.each do |symbol|
          f = send(symbol)
          if f.dimension > 0
            set.merge(f.decompose)
          else
            set << f
          end
        end
      end
    end
    set
  end

end # Domain


end # Cubic
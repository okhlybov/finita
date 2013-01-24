require 'set'
require 'symbolic'
require 'data_struct'
require 'finita/symbolic'
require 'finita/generator'


module Finita::Domain
end # Finita::Domain


module Finita::Domain::Cubic


StaticCode = Class.new(DataStruct::Code) do
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
      FINITA_INLINE size_t #{index}(#{type}* self, int x, int y, int z) {
        #{assert}(#{within}(self, x, y, z));
        return (x-self->x1) + (self->y2-self->y1+1)*((y-self->y1) + (z-self->z1)*(self->x2-self->x1+1));
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
      }
      int #{within}(#{type}* self, int x, int y, int z) {
        #{assert}(self);
        return (self->x1 <= x && x <= self->x2) && (self->y1 <= y && y <= self->y2) && (self->z1 <= z && z <= self->z2);
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
        #{assert}(self);
        #{assert}(area);
        self->area = area;
        self->index = 0;
      }
      int #{itHasNext}(#{it}* self) {
        return self->index < #{size}(self->area);
      }
      #{node} #{itNext}(#{it}* self) {
        return self->area->nodes[self->index++];
      }
    $
  end
end.new('FinitaCubicArea') # StaticCode


class Area
  Empty = [0,0]
  attr_reader :xrange, :yrange, :zrange
  def initialize(xs = nil, ys = nil, zs = nil)
    @xrange = Area.coerce(xs)
    @yrange = Area.coerce(ys)
    @zrange = Area.coerce(zs)
  end
  def hash
    self.class.hash ^ (xrange.hash << 1) ^ (yrange.hash << 2) ^ (zrange.hash << 3) # TODO
  end
  def ==(other)
    equal?(other) || self.class == other.class && xrange == other.xrange && yrange == other.yrange && zrange == other.zrange
  end
  alias :eql? :==
  def code(problem_code)
    Code.new(self, problem_code)
  end
  private
  def self.coerce(obj)
    if obj.nil?
      Empty
    else
      obj.is_a?(Array) ? [Finita.simplify(obj.first), Finita.simplify(obj.last)] : [Finita.simplify(0), Finita.simplify(obj-1)]
    end
  end
  class Code < DataStruct::Code
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
      super + [StaticCode] + Collector.new.apply!(*(@area.xrange + @area.yrange + @area.zrange)).instances.collect {|o| o.code(@problem_code)}
    end
    def initialize(area, problem_code)
      @area = area
      @instance = "#{StaticCode.type}#{@@count += 1}"
      @problem_code = problem_code
      super(StaticCode.type)
      problem_code.initializers << self
    end
    def hash
      @area.hash
    end
    def eql?(other)
      equal?(other) || self.class == other.class && @area == other.instance_variable_get(:@area)
    end
    def write_intf(stream)
      stream << %$
      extern #{type} #{instance};
    $
    end
    def write_defs(stream)
      stream << %$
      #{type} #{instance};
    $
    end
    def write_initializer(stream)
      args = (@area.xrange + @area.yrange + @area.zrange).collect {|e| CEmitter.new.emit!(e)}.join(',')
      stream << %$
      #{ctor}(&#{instance}, #{args});
    $
    end
  end # Code
end # Area


end # Finita::Domain
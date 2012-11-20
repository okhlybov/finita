require 'singleton'
require 'data_struct'


module Finita


class RectField3D < DataStruct::Struct
  def write_intf(stream)
    stream << %$
      typedef struct #{type} #{type};
      struct #{type} {
        #{elementType}* data;
        int x1, x2, y1, y2, z1, z2;
        size_t size;
      };
      void #{ctor}(#{type}*, int, int, int, int, int, int);
      int #{within}(#{type}*, int, int, int);
      size_t #{size}(#{type}*);
      static #{elementType}* #{ref}(#{type}* self, int x, int y, int z) {
        #{assert}(self);
        #{assert}(#{within}(self, x, y, z));
        return &self->data[(x-self->x1) + (self->y2-self->y1+1)*((y-self->y1) + (z-self->z1)*(self->x2-self->x1+1))];
      }
      static #{elementType} #{get}(#{type}* self, int x, int y, int z) {
        #{assert}(self);
        #{assert}(#{within}(self, x, y, z));
        return *#{ref}(self, x, y, z);
      }
      static void #{set}(#{type}* self, int x, int y, int z, #{elementType} value) {
        #{assert}(self);
        #{assert}(#{within}(self, x, y, z));
        *#{ref}(self, x, y, z) = value;
      }
      void #{foreach}(#{type}*, int(*)(#{elementType}, int, int, int));
    $
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(#{type}* self, int x1, int x2, int y1, int y2, int z1, int z2) {
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
        self->data = (#{elementType}*)#{calloc}(self->size, sizeof(#{elementType})); #{assert}(self->data);
      }
      int #{within}(#{type}* self, int x, int y, int z) {
        #{assert}(self);
        return (self->x1 <= x && x <= self->x2) && (self->y1 <= y && y <= self->y2) && (self->z1 <= z && z <= self->z2);
      }
      size_t #{size}(#{type}* self) {
        #{assert}(self);
        return self->size;
      }
      void #{foreach}(#{type}* self, int(*fp)(#{elementType} value, int x, int y, int z)) {
        int x, y, z;
        #{assert}(self);
        for(x = self->x1; x <= self->x2; ++x)
        for(y = self->y1; y <= self->y2; ++y)
        for(z = self->z1; z <= self->z2; ++z)
          if(!fp(*#{ref}(self, x, y, z), x, y, z)) break;
      }
    $
  end
end # RectField3D


class IntegerRectField < RectField3D
  include Singleton
  def initialize
    super('FinitaIntegerRectField', 'int')
  end
end # IntegerRectField


class FloatRectField < RectField3D
  include Singleton
  def initialize
    super('FinitaFloatRectField', 'double')
  end
end # IntegerRectField


class ComplexRectField < RectField3D
  include Singleton
  def initialize
    super('FinitaComplexRectField', '_Complex double')
  end
  def write_intf(stream)
    stream << %$
      #include <complex.h>
    $
    super
  end
end # ComplexRectField


RectFieldCode = {
  ::Integer => IntegerRectField.instance,
  ::Float => FloatRectField.instance,
  ::Complex => ComplexRectField.instance
}


end # Finita
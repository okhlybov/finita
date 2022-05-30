require 'autoc/vector'
require 'finita/core'
require 'finita/grid'
require 'finita/field'


module Finita::Grid2


  NODE = Finita::Node.new :XY, %i[x y]
  NODE_VECTOR = AutoC::Vector.new :XYVector, NODE


  class Cartesian < Finita::Grid::Base

    include Finita::Instantiable
    
    def copyable? = false
    def custom_constructible? = false
    def default_constructible? = false

    def nodes = NODE_VECTOR

    def field(scalar, **kws) = Finita::Field.new(self, scalar, **kws)

    def initialize(type = :Cartesian2, visibility: :public)
      super(type, { x1: :int, x2: :int, y1: :int, y2: :int, nx: :int, ny: :int, nodes: }, visibility:)
      @omit_accessors = true
    end

    def interface_definitions(stream)
      stream << %{
        /**
          @brief Macro to traverse through the #{type} grid instance
        */
        #define #{decorate_identifier :for}(grid) \\
          _Pragma("omp for") for(int y = (grid)->y1; y <= (grid)->y2; ++y) \\
            _Pragma("omp simd") for(int x = (grid)->x1; x <= (grid)->x2; ++x)
      }
      super
    end

    def configure
      super
      def_method :void, :create, { self: type, x1: :int, x2: :int, y1: :int, y2: :int } do
        code %{
          assert(self);
          assert(x1 < x2);
          assert(y1 < y2);
          *self = (#{type}) {x1, x2, y1, y2, x2-x1+1, y2-y1+1};
          #{nodes.create_size}(&self->nodes, self->nx*self->ny);
          #{decorate_identifier :for}(self) {
            const #{node.type} n = {x, y};
            #{nodes.set}(&self->nodes, #{index}(self, n), n);
          }
        }
      end
      def_method :void, :create_n, { self: type, nx: :size_t, ny: :size_t } do
        code %{
          assert(self);
          #{create}(self, 0, nx-1, 0, ny-1);
        }
      end
      index.inline_code %{
        assert(self);
        assert(self->x1 <= node.x && node.x <= self->x2);
        assert(self->y1 <= node.y && node.y <= self->y2);
        return self->nx*(node.y-self->y1) + (node.x-self->x1);
      }
    end

  end


end
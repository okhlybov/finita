require 'autoc/vector'
require 'finita/core'
require 'finita/field'


module Finita::Grid2


  NODE = Finita::Node.new :XY, %i[x y]
  
  
  NODE_VECTOR = AutoC::Vector.new :XYVector, NODE


  class Cartesian < AutoC::Structure

    include Finita::Instantiable
    
    prepend AutoC::Composite::Traversable

    def copyable? = false
    def custom_constructible? = false
    def default_constructible? = false

    def node = NODE

    def element = node

    def nodes = NODE_VECTOR

    def field(scalar, **kws) = Finita::Field.new(self, scalar, **kws)

    def initialize(type = :Cartesian2, visibility: :public)
      super(type, { x1: :int, x2: :int, y1: :int, y2: :int, nx: :int, ny: :int, nodes: }, visibility:)
      @omit_accessors = true
    end

    def interface_definitions(stream)
      stream << %{
        /**
          @brief Macro to traverse over #{type} instance
        */
        #define #{decorate_identifier :for}(grid) \\
          for(int y = (grid)->y1; y <= (grid)->y2; ++y) \\
            _Pragma("omp simd") \\
            for(int x = (grid)->x1; x <= (grid)->x2; ++x)
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
      def_method :size_t, :index, { self: const_type, node: node.const_type } do
        inline_code %{
          assert(self);
          assert(self->x1 <= node.x && node.x <= self->x2);
          assert(self->y1 <= node.y && node.y <= self->y2);
          return self->nx*(node.y-self->y1) + (node.x-self->x1);
        }
      end
      def_method :size_t, :index_count, { self: const_type } do
        inline_code %{
          assert(self);
          return #{nodes.size}(&self->nodes);
        }
      end
      def_method node.type, :node, { self: const_type, index: :size_t } do
        inline_code %{
            assert(self);
            return #{nodes.get}(&self->nodes, index);
        }
      end
    end
  end


  class Cartesian::Range < AutoC::Range::Forward

    private def node_range = @node_range ||= iterable.send(:nodes).range
    
    def composite_interface_declarations(stream)
      stream << %{
        /**
          @brief
        */
        typedef struct {
          #{node_range.type} node_range; /**< @private */
        } #{type};
      }
    end

    private def configure
      super
      custom_create.inline_code %{
        assert(self);
        assert(iterable);
        #{node_range.create}(&self->node_range, &iterable->nodes);
      }
      empty.inline_code %{
        assert(self);
        return #{node_range.empty}(&self->node_range);
      }
      pop_front.inline_code %{
        assert(self);
        #{node_range.pop_front}(&self->node_range);
      }
      view_front.inline_code %{
        assert(self);
        return #{node_range.view_front}(&self->node_range);
      }
    end
  end


end
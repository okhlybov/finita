require 'autoc/std'
require 'autoc/record'
require 'autoc/vector'


require 'finita/nodes'


module Finita::Grid
  

  class CartesianXY < AutoC::Record

    using AutoC::STD::Coercions

    def node = Finita::XY
    def nodes = Finita::VECTOR_XY

    def destructible? = true
    def default_constructible? = false
    def custom_constructible? = false

    def initialize(name = :CXY)
      super(name, { first: node, last: node, nodes: nodes })
    end

    def render_interface(stream)
      super
      stream << %{
        /**
          @brief Fast traverser macro over grid
        */
        #define #{self}_FOREACH(grid) \\
          _Pragma("omp for") for(int y = (grid)->first.y; y <= (grid)->last.y; ++y) \\
          _Pragma("omp simd") for(int x = (grid)->first.x; x <= (grid)->last.x; ++x)
      }
    end

    def configure
      super
      method(:size_t, :index, { target: const_rvalue, node: node.const_rvalue }).configure do
        code %{
          assert(target);
          assert(target->first.x <= node->x && node->x <= target->last.x);
          assert(target->first.y <= node->y && node->y <= target->last.y);
          return (target->last.x - target->first.x + 1)*(node->y - target->first.y) + (node->x - target->first.x);
        }
      end
      method(node, :node, { target: const_rvalue, index: :size_t.const_rvalue }).configure do
        code %{
          assert(target);
          return *#{nodes.view.('target->nodes', index)};
        }
      end
      method(:size_t, :size, { target: const_rvalue }).configure do
        code %{
          assert(target);
          return (target->last.x - target->first.x + 1)*(target->last.y - target->first.y + 1);
        }
      end
      method(:void, :create, { target: lvalue, first: node.const_rvalue, last: node.const_rvalue }).configure do
        code %{
          assert(target);
          assert(first->x < last->x);
          assert(first->y < last->y);
          target->first = *first;
          target->last = *last;
          #{nodes.custom_create.('target->nodes', size.(target))};
          size_t i = 0;
          #{type}_FOREACH(target) {
            #{nodes.set.('target->nodes', 'i++', "(#{node}){x,y}")};
          }
        }
      end
      destroy.configure do
        code %{
          assert(target);
          #{nodes.destroy.('target->nodes')};
        }
      end
      method(:void, :create_WH, { target: lvalue, width: :int.const_rvalue, height: :int.const_rvalue }).configure do
        code %{
          assert(target);
          #{create.(target, "(#{node}){0,0}", "(#{node}){width-1,height-1}")};
        }
      end
    end

  end # CartesianXY


  CXY = CartesianXY.new


end # Grid
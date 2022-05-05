# frozen_string_literal: true


require 'finita/core'
require 'autoc/vector'
require 'autoc/hash_map'
require 'autoc/composite'
require 'autoc/structure'


module Finita::Grid


  XY = AutoC::Structure.new :XY, { x: :int, y: :int }, profile: :glassbox


  XY_VECTOR = AutoC::Vector.new :XYVector, XY


  XYZ = AutoC::Structure.new :XYZ, { x: :int, y: :int, z: :int }, profile: :glassbox


  # @abstract
  class Generic < AutoC::Structure

    private attr_reader :_node
    private def _i2n = @_i2n ||= AutoC::Vector.new(decorate_identifier(:_V), _node, visibility: :internal)
    private def _n2i = @_n2i ||= AutoC::HashMap.new(decorate_identifier(:_M), _node, :size_t, visibility: :internal)

    def initialize(type, node:, visibility: :public)
      super(type, {}, visibility:, profile: :blackbox)
      @omit_accessors = true
      @_node = node
    end

    def configure
      self.fields = { nodes: _i2n, indices: _n2i }
      super
      def_method :size_t, :size, { self: const_type } do
        code %{
          assert(#{_i2n.size}(&self->nodes) == #{_n2i.size}(&self->indices));
          return #{_i2n.size}(&self->nodes);
        }
      end
      def_method :size_t, :index, { self: const_type, node: _node } do
        code %{
          assert(#{_n2i.contains_key}(&self->indices, node));
          return #{_n2i.get}(&self->indices, node);
        }
      end
      def_method _node, :node, { self: const_type, index: :size_t } do
        code %{
          assert(#{_i2n.check_position}(&self->nodes, index));
          return #{_i2n.get}(&self->nodes, index);
        }
      end
    end
  end


  class Cartesian2 < AutoC::Structure

    prepend AutoC::Composite::Traversable

    def copyable? = false
    def default_constructible? = false

    def node = XY

    def element = node

    private def nodes = XY_VECTOR

    def initialize(type = :Cartesian2, visibility: :public)
      super(type, { x1: :int, x2: :int, y1: :int, y2: :int, nodes: }, visibility:)
      @omit_accessors = true
    end

    def configure
      super
      def_method :void, :create, { self: type, x1: :int, x2: :int, y1: :int, y2: :int } do
        code %{
          assert(self);
          assert(x1 < x2);
          assert(y1 < y2);
          *self = (#{type}) {x1, x2, y1, y2};
          #{nodes.create_size}(&self->nodes, (x2-x1+1)*(y2-y1+1));
          for(int x = self->x1; x <= self->x2; ++x) {
            for(int y = self->y1; y <= self->y2; ++y) {
              const #{node.type} n = {x, y};
              #{nodes.set}(&self->nodes, #{index}(self, n), n);
            }
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
          return (self->x2-self->x1+1)*node.y + (node.x-self->x1);
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


  class Cartesian2::Range < AutoC::Range::Forward

    private def node_range = @node_range ||= iterable.send(:nodes).range
    
    def composite_interface_declarations(stream)
      stream << %{
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
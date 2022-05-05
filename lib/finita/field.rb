# frozen_string_literal: true


require 'autoc/composite'
require 'finita/grid'


module Finita


  class Field < AutoC::Composite

    attr_reader :grid

    attr_reader :scalar

    include Finita::Pristine

    def destructible? = true

    def initialize(grid, scalar = :double, type: grid.decorate_identifier(scalar), visibility: :public)
      super(type, visibility:)
      @scalar = AutoC::Type.coerce(scalar)
      @grid = grid
    end

    def composite_interface_declarations(stream)
      super
      stream << %{
        typedef struct {
          #{scalar.type}** layers; /**< @private */
          size_t layer_count; /**< @private */
          #{grid.const_ptr_type} grid; /**< @private */
        } #{type};
      }
    end

    private def configure
      dependencies << scalar << grid
      super
      def_method :void, :create, { self: type, grid: grid.const_ptr_type, layer_count: :size_t }, instance: :custom_create do
        code %{
          assert(self);
          assert(grid);
          assert(layer_count > 0);
          self->grid = grid;
          self->layer_count = layer_count;
          self->layers = #{memory.allocate(scalar.ptr_type, :layer_count)};
          const size_t layer_size = #{grid.index_count}(self->grid);
          for(size_t i = 0; i < self->layer_count; ++i) self->layers[i] = #{memory.allocate(scalar.type, :layer_size, true)};
          }
      end
      destroy.code %{
        assert(self);
        for(size_t i = 0; i < self->layer_count; ++i) #{memory.free('self->layers[i]')};
        #{memory.free('self->layers')};
      }
      def_method scalar.ptr_type, :view, { self: type, node: grid.node.const_type, layer: :size_t } do
        inline_code %{
          assert(self);
          assert(layer < self->layer_count);
          return &self->layers[layer][#{grid.index}(self->grid, node)];
        }
      end
      def_method scalar.ptr_type, :view0, { self: type, node: grid.node.const_type } do
        inline_code %{
          assert(self);
          return &self->layers[0][#{grid.index}(self->grid, node)];
        }
      end
      def_method :void, :rotate_n, { self: type, times: :unsigned } do
        code %{
          assert(self);
          assert(times > 0);
          /* Cyclic layers rotation */
          if(self->layer_count > 1) {
            while(times-- > 0) {
              #{scalar.ptr_type} last = self->layers[self->layer_count-1];
              for(size_t i = self->layer_count-1; i > 0; --i) self->layers[i] = self->layers[i-1];
              self->layers[0] = last;
            }
          }
        }
      end
      def_method :void, :rotate, { self: type } do
        code %{
          #{rotate_n}(self, 1);
        }
      end
    end
  end


end
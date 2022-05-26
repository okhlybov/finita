# frozen_string_literal: true


require 'finita/core'
require 'autoc/composite'


module Finita


  class Field < AutoC::Composite

    include Finita::Pristine
    include Finita::Instantiable

    attr_reader :grid

    attr_reader :scalar

    def destructible? = true
    def custom_constructible? = false
    def default_constructible? = false

    def memory = AutoC::Allocator::Aligning.instance

    def initialize(grid, scalar = :double, type: grid.decorate_identifier(scalar), visibility: :public)
      super(type, visibility:)
      @scalar = AutoC::Type.coerce(scalar)
      @grid = grid
    end

    def instance(identifier = "_field#{@@count+=1}_", visibility: :public) = Field::Instance.new(self, identifier, visibility:)

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

    def composite_interface_definitions(stream)
      super
      stream << %{
        /**
          @brief Macro to traverse through the #{self} field instance
        */
        #define #{decorate_identifier :for}(field) #{grid.decorate_identifier :for}((field)->grid)
      }
    end

    def definitions(stream)
      stream << %{
        #include <tgmath.h>
      }
      super
    end

    private def configure
      dependencies << scalar << grid
      super
      def_method :void, :create, { self: type, grid: grid.const_type, layer_count: :size_t }, refs: 2 do
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
      def_method :int, :converge_ex, { self: const_type, rtol: :double, atol: :double, n1: :size_t, n2: :size_t } do
        code %{
          assert(self);
          assert(rtol >= 0);
          assert(atol >= 0);
          double norm12 = 0, norm2 = 0;
          #{grid.range.type} r = #{grid.range.new}(self->grid); /* Create a serial range covering entire grid to be cloned per section */
          #pragma omp parallel sections firstprivate(r)
          {
            #pragma omp section
            {
              size_t i = 0;
              for(; !#{grid.range.empty}(&r); #{grid.range.pop_front}(&r), ++i) {
                #{grid.node.const_type} n = *#{grid.range.view_front}(&r);
                norm2 = (norm2*i + pow(*#{view}((#{ptr_type})self, n, n2), 2))/(i+1);
              }
            }
            #pragma omp section
            {
              size_t i = 0;
              for(; !#{grid.range.empty}(&r); #{grid.range.pop_front}(&r), ++i) {
                #{grid.node.const_type} n = *#{grid.range.view_front}(&r);
                norm12 = (norm12*i + pow(*#{view}((#{ptr_type})self, n, n1) - *#{view}((#{ptr_type})self, n, n2), 2))/(i+1);
              }
            }
          }
          return norm12 < rtol*norm2 + atol;
        }
      end
      def_method :int, :converge, { self: const_type, rtol: :double, atol: :double } do
        code %{
          return #{converge_ex}(self, rtol, atol, 0, 1);
        }
      end
    end
  end


  class Field::Instance < Finita::Instantiable::Instance

    def create(grid, layer_count = 1) = super grid, @layer_count = layer_count

    private def instance_definitions(stream)
      super
      node = type.grid.node.type
      fields = type.grid.node.items.join(',')
      defs = [
        %{
          /**
            @brief
          */
          #define #{identifier}_n(t,#{fields}) (*#{type.view}(&#{identifier},(#{node}){#{fields}},t))
        },
        %{
          /**
            @brief
          */
          #define #{identifier}(#{fields}) #{identifier}_n(0,#{fields})
        }
      ]
      if @layer_count > 1
        defs << %{
          /**
            @brief
          */
          #define #{identifier}_(#{fields}) #{identifier}_n(1,#{fields})
        }
      end
      if @layer_count > 2
        defs << %{
          /**
            @brief
          */
          #define #{identifier}__(#{fields}) #{identifier}_n(2,#{fields})
        }
      end
      defs.each { |x| stream << x }
    end
  end

end
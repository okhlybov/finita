# frozen_string_literal: true


require 'finita/core'
require 'autoc/vector'
require 'autoc/hash_map'
require 'autoc/composite'
require 'autoc/structure'


module Finita::Grid


  # @private
  # @abstract
  # Common base for all regular grids
  class Base < AutoC::Structure

    prepend AutoC::Composite::Traversable

    def node  = nodes.element
    def nodes = @nodes ||= AutoC::Vector.new(decorate_identifier(:_V), node, visibility:) # FIXME force internal visibility

    def element = node # Method employed be the generic range type

    def configure
      super
      def_method :size_t, :size, { self: const_type } do
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
      def_method :size_t, :index, { self: const_type, node: node.const_type }
    end

  end

  # Unified range type for regular grids
  class Base::Range < AutoC::Range::Forward

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
      take_front.inline_code %{
        assert(self);
        return #{node_range.take_front}(&self->node_range);
      }
    end
  end


  # @abstract
  # Class representing generic node <-> index mapping type.
  class GenericMapping < Base

    attr_reader :node

    def indices = @indices ||= AutoC::HashMap.new(decorate_identifier(:_M), node, :size_t, visibility: :internal)

    def initialize(type, node:, visibility: :public)
      super(type, {}, visibility:, profile: :blackbox)
      @omit_accessors = true
      @node = node
    end

    def composite_interface_definitions(stream)
      super
      lookup_list = node.items.collect { |t| "#{t} = #{_lookup}(grid, __current__).#{t}"}.join(',')
      stream << %{
        /**
          @brief Macro to traverse through the #{type} grid instance
        */
        #define #{decorate_identifier :for}(grid) \\
          for( \\
            int __current__ = #{_first_index}(grid), __last__ = #{_last_index}(grid), \\
            #{lookup_list}; \\
            __current__ <= __last__; \\
            ++__current__, \\
            #{lookup_list} \\
          )
        /** @private */
        #{define} int #{_first_index}(#{const_ptr_type} self) {
          #ifdef _OPENMP
            int chunk_count;
            if(omp_in_parallel() && (chunk_count = omp_get_num_threads()) > 1) {
              const int chunk_id = omp_get_thread_num();
              const size_t chunk_size = #{size}(self) / omp_get_num_threads();
              return chunk_id*chunk_size;
            } else {
          #endif
              return 0;
          #ifdef _OPENMP
            }
          #endif
        }
        /** @private */
        #{define} int #{_last_index}(#{const_ptr_type} self) {
          #ifdef _OPENMP
            int chunk_count;
            if(omp_in_parallel() && (chunk_count = omp_get_num_threads()) > 1) {
              const int chunk_id = omp_get_thread_num();
              const size_t chunk_size = #{size}(self) / omp_get_num_threads();
              return chunk_id < chunk_count-1 ? (chunk_id+1)*chunk_size-1 : #{size}(self)-1;
            } else {
          #endif
              return #{size}(self)-1;
          #ifdef _OPENMP
            }
          #endif
        }
        /** @private */
        #{define} #{node} #{_lookup}(#{const_ptr_type} self, int index) {
          assert(index >= 0 && index < #{size}(self));
          return self->nodes.elements[index]; /* Excerpt from #{nodes.get}(&self->nodes, index) as this function might be private */
        }
      }
    end

    def configure
      self.fields = { nodes:, indices: }
      super
      index.code %{
        assert(#{indices.contains_key}(&self->indices, node));
        return #{indices.get}(&self->indices, node);
      }
    end
  end


end
# frozen_string_literal: true


require 'finita/core'
require 'autoc/vector'
require 'autoc/hash_map'
require 'autoc/composite'
require 'autoc/structure'


module Finita::Grid


  # @abstract
  # A base class representing generic node <-> index mapping type.
  class GenericMapping < AutoC::Structure

    private attr_reader :_node
    private def _i2n = @_i2n ||= AutoC::Vector.new(decorate_identifier(:_V), _node, visibility: :internal)
    private def _n2i = @_n2i ||= AutoC::HashMap.new(decorate_identifier(:_M), _node, :size_t, visibility: :internal)

    def initialize(type, node:, visibility: :public)
      super(type, {}, visibility:, profile: :blackbox)
      @omit_accessors = true
      @_node = node
    end

    def composite_interface_definitions(stream)
      super
      lookup_list = _node.items.collect { |t| "#{t} = #{_lookup}(grid, __current__).#{t}"}.join(',')
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
        #{define} #{_node} #{_lookup}(#{const_ptr_type} self, int index) {
          assert(index >= 0 && index < #{size}(self));
          return self->nodes.elements[index]; /* Excerpt from #{_i2n.get}(&self->nodes, index) as this function is private */
        }
      }
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


end
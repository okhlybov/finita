# frozen_string_literal: true


require 'singleton'
require 'autoc/std'
require 'autoc/hashers'
require 'finita/core'
require 'finita/matrix'


module Finita::Cartesian


  class N3 < Finita::Value

    # On data packing: http://www.catb.org/esr/structure-packing/

    include Singleton

    def initialize(*args, **kws)
      super(:N3)
      dependencies << AutoC::STD::ASSERT_H << AutoC::STD::INTTYPES_H << AutoC::STD::LIMITS_H << AutoC::Hashers.instance
    end

    def rc = @rc ||= Finita::Matrix::RC.new(self)

    def render_interface(stream)
      stream << %{
        typedef struct {
          /// @private
          union {
            uint64_t state; // used for fast contents-based comparison/ordering/hashing
            struct {
              unsigned short dx, dy, dz;
              unsigned short field;
            };
          };
        } #{signature};

        // ensure .state unambiguously represents the node state (no intermittent garbage is captured between fields, no extra padding etc.)
        static_assert(sizeof(#{signature}) == sizeof(uint64_t), "#{signature} must be unambiguously representable as uint64_t");

        #define #{prefix}(x,y,z,field) #{new!}(x,y,z,field)
        AUTOC_INLINE #{signature} #{new!}(short x, short y, short z, unsigned short field) {
          assert(SHRT_MIN <= x); assert(x <= SHRT_MAX);
          assert(SHRT_MIN <= y); assert(y <= SHRT_MAX);
          assert(SHRT_MIN <= z); assert(z <= SHRT_MAX);
          #{signature} target = {.dx = x + SHRT_MIN, .dy = y + SHRT_MIN, .dz = z + SHRT_MIN, .field = field};
          // store node indices as unsigned values to be able to compute ordering by the state's contents
          return target;
        }
        AUTOC_INLINE size_t #{hash!}(N3 target) {
          return autoc_hash(target.state);
        }
      }
    end

    def default_create = @default_create ||= -> (target) { "#{target} = #{new}(0, 0, 0, 0)" }

    def custom_create = @custom_create ||= -> (target, source) { copy.(target, source) }

    def copy = @copy ||= -> (target, source) { "#{target} = #{source}" }

    def equal = @equal ||= -> (lt, rt) { "((#{lt}).state == (#{rt}).state)" }

    def compare = @compare ||= -> (lt, rt) { "((#{lt}).state == (#{rt}).state ? 0 : ((#{lt}).state < (#{rt}).state ? -1 : +1))" }

    def hash_code = @hash_code ||= -> (target) { "#{hash!}(#{target})" }
  end # N3


end

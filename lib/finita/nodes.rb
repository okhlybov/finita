require 'autoc/std'
require 'autoc/vector'


module Finita

  class Node2D < AutoC::STD::Primitive

    def orderable? = false

    def render_interface(stream)
      stream << %{
        /**
          @public
          @brief 2D coordinate
        */
        typedef struct {
          int x, y;
        } #{self};
      }
    end

    def default_create = @default_create ||= -> (target) { "#{target} = (#{self}){0,0}" }
  
    def custom_create = @custom_create ||= -> (target, source) { copy.(target, source) }
  
    def copy = @copy ||= -> (target, source) { "#{target} = #{source}" }
  
    def equal = @equal ||= -> (lt, rt) { "(#{lt}).x == (#{rt}).x && (#{lt}).y == (#{rt}).y" }

    #def compare = @compare ||= -> (lt, rt) { "(#{lt} == #{rt} ? 0 : (#{lt} > #{rt} ? +1 : -1))" }
  
    def hash_code = @hash_code ||= -> (target) { "(size_t)((#{target}).x ^ (#{target}).y)" } # FIXME

  end

  XY = Node2D.new(:XY)

  VECTOR_XY = AutoC::Vector.new(:_VectorXY, XY, visibility: :internal)

end
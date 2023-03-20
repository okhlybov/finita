require 'autoc/record'


require 'finita/nodes'


module Finita::Grid
  

  class Cartesian < AutoC::Record
  end # Cartesian


  class CartesianXY < Cartesian

    def destructible? = true

    def initialize(name = :CXY)
      super(name, { first: Finita::XY, last: Finita::XY })
    end

    def render_interface(stream)
      super
      stream << %{
        /**
          @brief Fast traverser over grid
        */
        #define #{self}_FOREACH(grid) \\
          _Pragma("omp parallel for") for(int x = (grid).first.x; x < (grid).last.x; ++x) \\
          for(int y = (grid).first.y; y < (grid).last.y; ++y) \\
      }
    end

  end # CartesianXY


  CXY = CartesianXY.new


end # Grid
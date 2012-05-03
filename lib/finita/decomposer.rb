require 'finita/common'
require 'finita/mapper'
require 'finita/generator'


module Finita::Decomposer


class NonZeroBalancer

  class Code < Finita::CodeTemplate

    def entities; super + [Finita::NodeMapCode.instance, func_matrix_code] end

    attr_reader :name, :func_matrix_code

    def initialize(decomposer, gtor, system)
      @decomposer = decomposer
      @gtor = gtor
      @system = system
      @name = system.name
      @func_matrix_code = Finita::FuncMatrix::Code[system.type]
    end

    def write_intf(stream)
      stream << %$
        void #{name}SetupDecomposer();
      $
    end

    def write_defs(stream)
      stream << %$
        extern FinitaMapper #{name}Mapper;
        extern #{func_matrix_code.type} #{name}SymbolicMatrix;
        static FinitaNodeMap #{name}NonZeroPerRow;
        void #{name}SetupDecomposer() {

        }
      $
    end

  end # Code

  def bind(gtor, system)
    Code.new(self, gtor, system)
  end

end # NonZeroBalancer


end # Decomposer
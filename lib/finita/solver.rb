require 'finita/common'
require 'finita/generator'


module Finita::Solver


class Explicit

  class Code < Finita::BoundCodeTemplate
    attr_reader :system
    def entities; super + [Finita::Generator::StaticCode.instance, Finita::Ordering::StaticCode.instance] end
    def initialize(master, gtor, system)
      super(master, gtor)
      @system = system
    end
    def write_intf(stream)
      stream << "void #{system.name}Solve();"
    end
    def write_defs(stream)
      stream << "typedef #{Generator::Scalar[system.type]} (*#{system.name}Fp)(int, int, int);"
      stream << %$
        extern FinitaOrdering #{system.name}Ordering;
        extern FinitaFpVector #{system.name}FpVector;
        void #{system.name}Solve() {
          int index, size = FinitaOrderingSize(&#{system.name}Ordering);
          for(index = 0; index < size; ++index) {
            FinitaFpListIt it;
            #{Generator::Scalar[system.type]} result = 0;
            FinitaNode node = FinitaOrderingNode(&#{system.name}Ordering, index);
            FinitaFpListItCtor(&it, FinitaFpVectorGet(&#{system.name}FpVector, index));
            while(FinitaFpListItHasNext(&it)) {
              result += ((#{system.name}Fp)FinitaFpListItNext(&it))(node.x, node.y, node.z);
            }
            #{system.name}SetNode(result, node);
          }
        }
      $
    end
  end # Code

  def bind(gtor, system)
    Code.new(self, gtor, system) unless gtor.bound?(self)
  end

end # Explicit


end # Finita::Solver
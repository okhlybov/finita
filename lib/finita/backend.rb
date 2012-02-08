require 'finita/common'


module Finita


class SuperLU

  class StaticCode < StaticCodeTemplate
    def entities; super + [Generator::StaticCode.instance] end
    def write_intf(stream)
      stream << %q^
        #define FINITA_BACKEND_SUPERLU
      ^
    end
    def write_decls(stream)
      stream << %q^
        /*#include "superlu_ddefs.h"*/
      ^
    end
  end # StaticCode

  class Code < BoundCodeTemplate
    def entities; super + [StaticCode.instance, system_code] end
    def system_code; gtor[@system] end
    def initialize(master, gtor, system)
      super(master, gtor)
      @system = system
    end
  end # Code

  def bind(gtor, system)
    Code.new(self, gtor, system) unless gtor.bound?(self)
  end

end # SuperLU


end # Finita
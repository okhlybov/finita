import sys
import autoc.module


_context = None


#
class Module(autoc.module.Module):
  
  def __enter__(self):
    self.__context = sys.modules[__name__]._context
    sys.modules[__name__]._context = self
    return super().__enter__()
    
  def __exit__(self, *args):
    x = super().__exit__(*args)
    sys.modules[__name__]._context = self.__context
    return x
  
  
#
class Entity(autoc.module.Entity):
  
    def __init__(self, *args, **kws):
      super().__init__(*args, **kws)
      if _context:
        _context.add(self)
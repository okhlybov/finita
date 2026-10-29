import sys
import metac.core
import metac.module


_context = None


#
class Module(metac.module.Module):
  
  def __enter__(self):
    self.__context = sys.modules[__name__]._context
    sys.modules[__name__]._context = self
    return super().__enter__()
    
  def __exit__(self, *args):
    x = super().__exit__(*args)
    sys.modules[__name__]._context = self.__context
    return x
  
  
#
class Entity(metac.module.Entity):
  
    def __init__(self, *args, **kws):
      super().__init__(*args, **kws)
      if _context:
        _context.add(self)
        
        
#
class Variable(metac.core.Variable, Entity):
  
  def __init__(self, type, name, *args, default=None, **kws):
    t = metac.core._type(type)
    super().__init__(type, name, *args, dependencies=(t, metac.core._linkage_code), **kws)
    self.default = default
    
  def render_declarations(self, stream, header):
    super().render_declarations(stream, header)
    if header:
      stream.append(f"METAC_EXTERN {self.definition};")

  def render_definitions(self, stream, header):
    super().render_definitions(stream, header)
    if not header:
      stream.append(f"{self.definition}{f" = {self.default}" if self.default else str()};")
      
      
#
def int(name, value=0):
  return Variable("int", name, default=value)


  #
def double(name, value=0):
  return Variable("double", name, default=value)
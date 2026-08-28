import sys
import finita.module


_context = None


#
class Problem(finita.module.Entity):
  
  def __init__(self, name, *args, **kws):
    super().__init__(*args, **kws)
    self.name = str(name)

  def __enter__(self):
    self.__context = sys.modules[__name__]._context
    sys.modules[__name__]._context = self
    
  def __exit__(self, *args):
    sys.modules[__name__]._context = self.__context
    return False
  
  
#
class Entity(finita.module.Entity):
  
  def __init__(self, *args, **kws):
    super().__init__(*args, **kws)
    if _context:
      _context.dependencies.add(self)
      
  def render_declarations(self, stream, header):
    super().render_declarations(stream, header)
    if header:
      self._render_interface(stream)
      
  def render_definitions(self, stream, header):
    super().render_definitions(stream, header)
    if not header:
      self._render_definitions(stream)
    
  def _render_interface(self, stream): pass
  
  def _render_definitions(self, stream): pass
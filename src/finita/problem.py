import sys
import finita.module
import autoc.composite


_context = None


#
class Problem(autoc.composite.Composite, finita.module.Entity):
  
  _managed = set()
  
  def __setup__(self):
    super().__setup__()
    
    with self.create as f:
      f.code = lambda: self._create_c()
      
    with self.destroy as f:
      f.code = lambda: self._destroy_c()

  def _create_c(self):
    code = ["assert(target);"]
    for e in sorted(self._managed):
      e._render_setup(code)
    return "".join(code)
      
  def _destroy_c(self):
    code = ["assert(target);"]
    for e in sorted(self._managed, reverse=True):
      e._render_cleanup(code)
    return "".join(code)
    
  def render_declarations(self, stream, header):
    super().render_declarations(stream, header)
    if header:
      stream.append(f"""
        typedef struct {{
          int _;
        }} {self};
      """)
      
  def __enter__(self):
    self.__context = sys.modules[__name__]._context
    sys.modules[__name__]._context = self
    return self
    
  def __exit__(self, *args):
    sys.modules[__name__]._context = self.__context
    return False
  
  @property
  def copyable(self):
    return False
  
  @property
  def comparable(self):
    return False
  
  @property
  def orderable(self):
    return False
  
  @property
  def hashable(self):
    return False
  
#
class Entity(finita.module.Entity):
  
  def __init__(self, *args, **kws):
    super().__init__(*args, **kws)
    if _context:
      self._problem_attach(_context)
     
  def _problem_attach(self, problem):
    problem.dependencies.add(self)
    
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


class Managed(Entity):
  
  _setup_c = None
  _cleanup_c = None

  def create(self, *args, **kws):
    self._problem._managed.add(self)

  def _problem_attach(self, problem):
    super()._problem_attach(problem)
    self._problem = problem
  
  def _render_setup(self, stream):
    if self._setup_c:
      stream.append(self._setup_c)

  def _render_cleanup(self, stream):
    if self._cleanup_c:
      stream.append(self._cleanup_c)
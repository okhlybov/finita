import autoc.std as std
from autoc.core import out, inout, Indirection
from autoc.memory import Manager
from autoc.reference import Arc
from autoc.composite import Composite, _StructRenderer


#
class _Field(_StructRenderer, Composite):
  
  def __init__(self, scalar, mesh, *args, name=None, memory=Manager(), **kws):
    super().__init__(name if name else mesh.decorate("field"), *args, dependencies=(scalar, mesh, memory, std.assert_h), **kws)
    self.memory = memory
    self.scalar = scalar
    self.mesh = mesh
    
  @property
  def comparable(self):
    return False
  
  @property
  def copyable(self):
    return False
  
  @property
  def hashable(self):
    return False
  
  @property
  def orderable(self):
    return False
  
  def __setup__(self):
    super().__setup__()
    
    _mesh = self.mesh.variable("target->mesh")

    with self.method(None, "create", {"target": out(self), "mesh": self.mesh}) as f:
      f.code = f"""
        assert(target);
        assert(mesh);
        target->elements = {self.memory.allocate(self.scalar, self.mesh.size(f.mesh), zero=True)}; assert(target->elements);
        {self.mesh.copy(_mesh, f.mesh)};
      """
      
    # Release of control data (elements + shared mesh) must accept a const handle,
    # exactly like Arc::free: keep the whole release chain const-correct.
    with self.method(None, "destroy", {"target": self}) as f:
      f.code = f"""
        assert(target);
        {self.memory.free("(void*)target->elements")};
        {self.mesh.destroy(_mesh)};
      """
      
      
  def _render_struct(self, stream):
    super()._render_struct(stream)
    if self.public:
      stream.append("/** @public */\n")
    stream.append(f"""typedef struct {{
      {Indirection(self.scalar)} elements; /**< @private */
      const {self.mesh} mesh; /**< @private */
    }} {self.name};
    """)
    
    
def Field(scalar, mesh):
  return Arc(_Field(scalar, mesh))
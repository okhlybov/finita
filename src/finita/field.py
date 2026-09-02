import finita.problem
import autoc.std as std
from autoc.reference import Arc
from autoc.memory import Manager
from autoc.composite import Composite, _StructRenderer
from autoc.core import out, inout, Callable, Indirection, Variable


#
class _Field(_StructRenderer, Composite):
  
  def __init__(self, scalar, mesh, *args, name=None, memory=Manager(), **kws):
    super().__init__(name if name else mesh.decorate("field"), *args, dependencies=(scalar, mesh, memory, std.assert_h), **kws)
    self.scalar = scalar
    self.memory = memory
    self.mesh = mesh
    self._layer = Indirection(self.scalar)
    self._layers = Indirection(self._layer)

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

    with self.method(None, "create", {"target": out(self), "mesh": self.mesh, "layers": "unsigned"}) as f:
      f.code = f"""
        assert(target);
        assert(mesh);
        assert(layers > 0);
        target->layer_count = layers;
        target->layers = {self.memory.allocate(Indirection(self.scalar), "layers")}; assert(target->layers);
        for(unsigned i = 0; i < layers; ++i) {{
          target->layers[i] = {self.memory.allocate(self.scalar, self.mesh.size(f.mesh), zero=True)}; assert(target->layers[i]);
        }}
        {self.mesh.copy(_mesh, f.mesh)};
      """
      
    with self.method(None, "destroy", {"target": self}) as f:
      f.code = f"""
        assert(target);
        for(unsigned i = 0; i < target->layer_count; ++i) {self.memory.free("target->layers[i]")};
        {self.memory.free("target->layers")};
        {self.mesh.destroy(_mesh)};
      """
      
    with self.method(Callable.Parameter(Indirection(self.scalar)), "access", {"target": inout(self), "node": self.mesh.node, "layer": "unsigned"}) as f:
      f.inline_code = f"""
        assert(target);
        assert(layer < target->layer_count);
        return &target->layers[layer][{self.mesh.index_of(_mesh, f.node)}];
      """
      
    with self.method(None, "rotate", {"target": inout(self), "direction": "int"}) as f:
      f.code = f"""
        assert(target);
        unsigned c = target->layer_count;
        if(c > 1) {{
          if(direction > 0) {{
            while(direction--) {{
              {self._layer} t = target->layers[c-1];
              for(unsigned i = c-1; i > 0; --i) target->layers[i] = target->layers[i-1];
              target->layers[0] = t;
            }}
          }} else
          if(direction < 0) {{
            while(direction++) {{
              {self._layer} t = target->layers[0];
              for(unsigned i = 0; i < c-1; ++i) target->layers[i] = target->layers[i+1];
              target->layers[c-1] = t;
            }}
          }}
        }}
      """

  def _render_struct(self, stream):
    super()._render_struct(stream)
    if self.public:
      stream.append("/** @public */\n")
    stream.append(f"""typedef struct {{
      {self._layers} layers; /**< @private */
      unsigned layer_count; /**< @private */
      const {self.mesh} mesh; /**< @private */
    }} {self.name};
    """)


#
class Field(Arc):
  
  def __init__(self, scalar, mesh):
    super().__init__(_Field(scalar, mesh))
    
  def instance(self, name):
    return Field.Instance(self, name)

  class Instance(Variable, finita.problem.Managed):
    
    def __init__(self, type, name, *args, **kws):
      super().__init__(type, name, *args, dependencies=(type,), **kws)

    def _render_interface(self, stream):
      super()._render_interface(stream)
      _node = self.type.mesh.node
      stream.append(f"""
        AUTOC_EXTERN {self.definition};
        #define {self.name}({_node._macro_access_decl_args}) *{self.type.access(self, _node._macro_access_pass_args, 0)}
        #define {self.name}_(layer, node) *{self.type.access(self, "node", "layer")}
      """)
      
    def _render_definitions(self, stream):
      super()._render_definitions(stream)
      stream.append(f"""
        {self.definition};
      """)
      
    def create(self, mesh, *args, layers=1, **kws):
      super().create(*args, **kws)
      self._setup_c = f"{self} = {self.type.new(mesh, layers)};"
      self._cleanup_c = f"{self.type.free(self)};"
      return self
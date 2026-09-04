import finita.object
import finita.problem
import autoc.std as std
from autoc.hash import XorRot
from autoc.memory import Manager
from autoc.core import Callable, Indirection, Variable, Primitive, Composite, _StructRenderer, out, inout


class _Entry(_StructRenderer, Primitive):
  
  def __init__(self, field, *args, dependencies=(), hasher=XorRot(), **kws):
    super().__init__(*args, dependencies=(*dependencies, field), visibility="internal", **kws)
    self.field = field
    self.hasher = hasher
    self._field = Indirection(field)
    field.references.add(self)
    
  def __setup__(self):
    super().__setup__()

    node = self.field.mesh.node
    
    with self.method(self, "new", {"target": inout(self.field), "node": node, "layer": std.unsigned}) as f:
      f.inline_code = f"""
        assert(target);
        {self} result;
        result.layer = layer;
        result.field = {f.target}; // a non-owned reference to a field
        {node.copy("result.node", f.node)};
        return result;
      """
    
    with self.method_from("equal", visibility="internal") as f:
      f.inline_code = f"""
        return
          {f.left}.field == {f.right}.field && // field value is treated by identity
          {node.equal(f"{f.left}.node", f"{f.right}.node")} &&
          {f.left}.layer == {f.right}.layer;
      """
      
    with self.method_from("hash", visibility="internal") as f:
      state = self.hasher.state_t.variable("state")
      f.code = f"""
        size_t result;
        {state.definition};
        {self.hasher.create(state)};
        result = {self.hasher.hash(state)};
        {self.hasher.update(state, f"(size_t){f.target}.field")}; // field value is treated by identity
        {self.hasher.update(state, node.hash(f"{f.target}.node"))};
        {self.hasher.update(state, f"{f.target}.layer")};
        {self.hasher.destroy(state)};
        return result;
      """
      
    with self.method(self.field.accessor, "access", {"target": self}) as f:
      f.inline_code = lambda: f"""
        return {self.field.access(f"{f.target}.field", f"{f.target}.node", f"{f.target}.layer")};
      """
      
      
  def _render_struct(self, stream):
    super()._render_struct(stream)
    if self.public:
      stream.append("/// @public\n")
    stream.append(f"""typedef struct {{
      {self._field} field; //< @private
      {self.field.mesh.node} node; //< @private
      unsigned layer; //< @private
    }} {self.name};""")


#
class _Field(_StructRenderer, Composite):
  
  def __init__(self, scalar, mesh, *args, name=None, memory=Manager(), **kws):
    super().__init__(name if name else mesh.decorate("field"), *args, dependencies=(scalar, mesh, memory, std.assert_h), **kws)
    self.scalar = scalar
    self.memory = memory
    self.mesh = mesh
    self.accessor = Callable.Parameter(Indirection(self.scalar))
    self.entry = _Entry(self, self._decorate_component("entry", abbreviate=False))
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

    with self.method(None, "create", {"target": out(self), "mesh": self.mesh, "layers": std.unsigned}) as f:
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
      
    with self.method(self.accessor, "access", {"target": inout(self), "node": self.mesh.node, "layer": std.unsigned}) as f:
      f.inline_code = f"""
        assert(target);
        assert(layer < target->layer_count);
        return &target->layers[layer][{self.mesh.index_of(_mesh, f.node)}];
      """
      
    with self.method(None, "rotate", {"target": inout(self), "direction": std.int}) as f:
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
      stream.append("/// @public\n")
    stream.append(f"""typedef struct {{
      {self._layers} layers; //< @private
      unsigned layer_count; //< @private
      const {self.mesh} mesh; //< @private
    }} {self.name};""")


#
class Field(finita.object.Object):
  
  def __init__(self, scalar, mesh, *args, **kws):
    super().__init__(_Field(scalar, mesh), *args, **kws)

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
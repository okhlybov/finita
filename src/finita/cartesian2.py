import functools
import autoc.std as std
from autoc.record import Record
from autoc.reference import Arc
from autoc.module import Code
from autoc.core import Primitive, Macro, Variable, out


#
class Node(Primitive):
  
  _macro_access_decl_args = "x,y"
  _macro_access_pass_args = "N2(x,y)"
  
  def __init__(self, *args, dependencies=(), **kws):
    self.coord_t = std.int
    super().__init__(*args, dependencies=(*dependencies, self.coord_t), **kws)
    
  def __setup__(self):
    super().__setup__()
    self.create = Macro.of(self.create, lambda target: f"{target} = {self.name}(0,0)")
    self.equal = Macro.of(self.equal, lambda left, right: f"({left}).x == ({right}).x && ({left}).y == ({right}).y")
    self.hash = Macro.of(self.hash, lambda target: f"({target}).x ^ ({target}).y") # FIXME
    
  def render_declarations(self, stream, header):
    super().render_declarations(stream, header)
    if header:
      stream.append(f"""
        typedef struct {{
          {self.coord_t} x;
          {self.coord_t} y;
        }} {self.name};
        #ifdef __cplusplus
          #define {self.name}(x,y) {self.name}{{x,y}}
        #else
          #define {self.name}(x,y) ({self.name}){{x,y}}
        #endif
      """)


#
node = Node("N2")


#
class _Mesh(Record):
  
  def __init__(self, name, **kws):
    self.node = node
    super().__init__(name, {"first": self.node, "last": self.node}, getters=False, setters=False, **kws)
    
  def __setup__(self):
    super().__setup__()

    with self.method(None, "create", {"target": out(self), "first": self.node, "last": self.node}) as f:
      f.code = f"""
        assert(target);
        assert(last.x >= first.x);
        assert(last.y >= first.y);
        *target = ({self}){{first, last}};
      """
      
    with self.method(std.size_t, "size", {"target": self}) as f:
      f.code = f"""
        assert(target);
        return (target->last.y - target->first.y + 1)*(target->last.x - target->first.x + 1);
      """
      
    with self.method(std.size_t, "index", {"target": self, "node": self.node}, attribute=("index", "of")) as f:
      f.inline_code = f"""
        assert(target);
        size_t result = (node.x - target->first.x) + (target->last.x - target->first.x + 1)*(node.y - target->first.y);
        assert(result < {self.size(f.target)});
        return result; 
      """
      
    with self.method(self.node, "node", {"target": self, "index": std.size_t}, attribute=("node", "of")) as f:
      f.inline_code = f"""
        assert(target);
        assert(index < {self.size(f.target)});
        size_t nx = target->last.x - target->first.x + 1;
        size_t dx = index % nx;
        size_t dy = (index - dx)/nx;
        return ({self.node}){{dx + target->first.x, dy + target->first.y}};  
      """


import finita.problem


#
@functools.cache
class Mesh(Arc):
  
  def __init__(self):
    super().__init__(_Mesh("C2"))
    
  def instance(self, name):
    return Mesh.Instance(self, name)

  def _render_struct(self, stream):
    super()._render_struct(stream)
    stream.append(f"""
      #ifdef __cplusplus
        #include <type_traits>
        #define _{self.type}_TYPE_CHECK(mesh) \\
          static_assert(std::is_convertible<decltype(mesh), {self}>::value || std::is_convertible<decltype(mesh), const {self}>::value, #mesh " must be of type {self}");
      #else
        #define _{self.type}_TYPE_CHECK(mesh) \\
          static_assert(_Generic((mesh), {self}:1, const {self}:1, default:0), #mesh " must be of type {self}");
      #endif
      #define {self.type}_FOREACH_XY(mesh) \\
        _{self.type}_TYPE_CHECK(mesh) \\
        _Pragma("omp for") \\
        for(int x = (mesh)->first.x; x <= (mesh)->last.x; ++x) \\
        _Pragma("omp simd") \\
        for(int y = (mesh)->first.y; y <= (mesh)->last.y; ++y)
      #define {self.type}_FOREACH_N(mesh) \\
        {self.type}_FOREACH_XY(mesh) \\
          for({self.node} n = {self.node}(x,y), *_ = &n; _; _ = NULL)
    """)
    
  class Instance(Variable, finita.problem.Entity):
    
    def __init__(self, type, name, *args, **kws):
      super().__init__(type, name, *args, dependencies=(type,), **kws)
      
    def _render_interface(self, stream):
      super()._render_interface(stream)
      stream.append(f"""
        AUTOC_EXTERN {self.definition};
      """)
      
    def _render_definitions(self, stream):
      super()._render_definitions(stream)
      stream.append(f"""
        {self.definition};
      """)
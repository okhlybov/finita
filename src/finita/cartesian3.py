import finita.object
import metac.std as std
from metac.record import Record
from metac.core import Primitive, Macro, Variable, out


#
class Node(Primitive, metaclass=finita.object._Cached):
  
  def __init__(self, *args, dependencies=(), **kws):
    self.coord_t = std.int
    super().__init__(*args, dependencies=(*dependencies, self.coord_t), **kws)
    self._macro_access_decl_args = "x,y,z"
    self._macro_access_pass_args = f"{self}(x,y,z)"
    
  def __setup__(self):
    super().__setup__()

    with self.method_from("create", visibility="private") as f:
      f.inline_code = f"""
        assert(target);
        *target = {self.name}(0, 0, 0);
      """

    with self.method_from("equal", visibility="private") as f:
      f.inline_code = f"""
        return left.x == right.x && left.y == right.y && left.z == right.z;
      """

    with self.method_from("compare", visibility="private") as f:
      f.inline_code = f"""
        if(left.x != right.x) return left.x < right.x ? -1 : 1;
        if(left.y != right.y) return left.y < right.y ? -1 : 1;
        if(left.z != right.z) return left.z < right.z ? -1 : 1;
        return 0;
      """

    with self.method_from("hash", visibility="private") as f:
      f.inline_code = f"""
        if (sizeof(size_t) >= 8) {{
          size_t h = ((size_t){f.target}.x) * 0x9e3779b97f4a7c15ULL
            + ((size_t){f.target}.y) * 0xbf58476d1ce4e5b9ULL
            + ((size_t){f.target}.z) * 0x94d049bb133111ebULL;
          return h ^ (h >> 32);
        }} else {{
          size_t h = ((size_t){f.target}.x) * 0x9e3779b1U
            + ((size_t){f.target}.y) * 0x85ebca6bU
            + ((size_t){f.target}.z) * 0xc2b2ae35U;
          return h ^ (h >> 16);
        }}
      """

  @property
  def zero_initializable(self):
    return True

  def render_declarations(self, stream, header):
    super().render_declarations(stream, header)
    if header:
      stream.append(f"""
        typedef struct {{
          {self.coord_t} x;
          {self.coord_t} y;
          {self.coord_t} z;
        }} {self.name};
        #ifdef __cplusplus
          #define {self.name}(x,y,z) {self.name}{{x,y,z}}
        #else
          #define {self.name}(x,y,z) ({self.name}){{x,y,z}}
        #endif
      """)

  def _create(self, args):
    value = ", ".join([str(x) for x in args])
    return f"{self.name}({value})"


#
class _Mesh(finita.object._Traitless, Record):
  
  def __init__(self, name, *args, node=Node("N3"), **kws):
    self.node = node
    super().__init__(name, {"first": self.node, "last": self.node}, *args, getters=False, setters=False, **kws)
    
  def __setup__(self):
    super().__setup__()

    with self.method(None, "create", {"target": out(self), "first": self.node, "last": self.node}) as f:
      f.code = f"""
        assert(target);
        assert(last.x >= first.x);
        assert(last.y >= first.y);
        assert(last.z >= first.z);
        *target = ({self}){{first, last}};
      """
      
    with self.method(std.size_t, "size", {"target": self}) as f:
      f.code = f"""
        assert(target);
        return (size_t)(target->last.z - target->first.z + 1)
             * (size_t)(target->last.y - target->first.y + 1)
             * (size_t)(target->last.x - target->first.x + 1);
      """
      
    with self.method(std.size_t, "index", {"target": self, "node": self.node}, attribute=("index", "of")) as f:
      f.inline_code = f"""
        assert(target);
        size_t nx = target->last.x - target->first.x + 1;
        size_t ny = target->last.y - target->first.y + 1;
        size_t dx = node.x - target->first.x;
        size_t dy = node.y - target->first.y;
        size_t dz = node.z - target->first.z;
        size_t result = dx + nx * (dy + ny * dz);
        assert(result < {self.size(f.target)});
        return result; 
      """
      
    with self.method(self.node, "node", {"target": self, "index": std.size_t}, attribute=("node", "of")) as f:
      f.inline_code = f"""
        assert(target);
        assert(index < {self.size(f.target)});
        size_t nx = target->last.x - target->first.x + 1;
        size_t ny = target->last.y - target->first.y + 1;
        size_t dx = index % nx;
        size_t rem = (index - dx) / nx;
        size_t dy = rem % ny;
        size_t dz = (rem - dy) / ny;
        return {self.node}(({self.node.coord_t})dx + target->first.x, ({self.node.coord_t})dy + target->first.y, ({self.node.coord_t})dz + target->first.z);
      """


#
class Mesh(finita.object.Object):

  _configuration = ("node",)

  def __init__(self, name="C3"):
    super().__init__(_Mesh(name))
    
  def instance(self, name):
    return Mesh.Instance(self, name)

  def _render_struct(self, stream, header):
    super()._render_struct(stream, header)
    stream.append(f"""
      #ifdef __cplusplus
        #include <type_traits>
        #define _{self.type}_TYPE_CHECK(mesh) \\
          static_assert(std::is_convertible<decltype(mesh), {self}>::value || std::is_convertible<decltype(mesh), const {self}>::value, #mesh " must be of type {self}");
      #else
        #define _{self.type}_TYPE_CHECK(mesh) \\
          static_assert(_Generic((mesh), {self}:1, const {self}:1, default:0), #mesh " must be of type {self}");
      #endif
      #define {self.type}_FOREACH_XYZ(mesh) \\
        _{self.type}_TYPE_CHECK(mesh) \\
        _Pragma("omp for collapse(2)") \\
        for(int z = (mesh)->first.z; z <= (mesh)->last.z; ++z) \\
        for(int y = (mesh)->first.y; y <= (mesh)->last.y; ++y) \\
          _Pragma("omp simd") \\
          for(int x = (mesh)->first.x; x <= (mesh)->last.x; ++x)
      #define {self.type}_FOREACH_N(mesh) \\
        {self.type}_FOREACH_XYZ(mesh) \\
          for({self.node} n = {self.node}(x,y,z), *_ = &n; _; _ = NULL)
    """)
    
  class Instance(Variable, finita.problem.Managed):
    
    def __init__(self, type, name, *args, **kws):
      super().__init__(type, name, *args, dependencies=(type,), **kws)

    def _render_cleanup(self, stream):
      stream.append(f"{self.type.free(self.name)};")

    def _render_interface(self, stream):
      super()._render_interface(stream)
      stream.append(f"""
        METAC_EXTERN {self.definition};
      """)
      
    def _render_definitions(self, stream):
      super()._render_definitions(stream)
      stream.append(f"""
        {self.definition};
      """)
      
    def create(self, first, last, *args, **kws):
      super().create(*args, **kws)
      self._setup_c = f"{self} = {self.type.new(self.type.node._create(first), self.type.node._create(last))};"
      self._cleanup_c = f"{self.type.free(self)};"
      return self

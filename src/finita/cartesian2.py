from autoc.reference import *
from autoc.composite import *
from autoc.record import *
from autoc.core import *
import autoc.std as std


#
class Node(Primitive):
  
  def __init__(self, *args, dependencies=(), **kws):
    self.coord_t = std.int
    super().__init__(*args, dependencies=(*dependencies, self.coord_t, std.size_t), **kws)
    
  def __setup__(self):
    super().__setup__()
    self.create = Macro.of(self.create, lambda target: f"{target} = ({self.name}){{0,0}}")
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
      """)


#
node = Node("N2")


#
class Grid(Record):
  
  def __init__(self, name):
    self.node = node
    super().__init__(name, {"first": self.node, "last": self.node}, getters=False, setters=False)
    
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


grid =  Arc(Grid("C2"))
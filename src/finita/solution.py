import autoc.list
import autoc.vector
import autoc.record
import finita.object
import autoc.std as std
from autoc.core import inout


#
class Builder(autoc.list.List):
  
  def __init__(self, field, *args, **kws):
    super().__init__(field._decorate_component(("solution", "builder"), abbreviate=True), field.entry, *args, **kws)
    
    
#
class _Solution(autoc.record.Record):
  
  def __init__(self, field, *args, name=None, **kws):
    self._fields = finita.object.Set(field._decorate_component(("solution", "fields")), field)
    self._entries = autoc.vector.Vector(field._decorate_component(("solution", "entries")), field.entry)
    self._indices = finita.object.Map(field._decorate_component(("solution", "indices")), std.size_t, field.entry)
    super().__init__(name if name else field._decorate_component("solution", abbreviate=False), {
      "fields": self._fields,
      "entries": self._entries,
      "indices": self._indices
    })
    self.field = field
    
  def __setup__(self):
    super().__setup__()
    
    with self.method(None, "register", {"target": inout(self), "entry": self.field.entry}) as f:
      f.code = f"""
        size_t index = 0;
        assert(target);
        {self._fields.put("&target->fields", "entry.field")}; // Take owenership over the input fields
        {self._indices.set("&target->indices", "entry", "index++")};
      """
      
    with self.method(None, "finalize", {"target": inout(self)}) as f:
      f.code = f"""
        assert(target);
        {self._entries.create_size("&target->entries", self._indices.size("&target->indices"))};
        for({self._indices.range} r = {self._indices.range.new("&target->indices")};;); // TODO
      """
      
      
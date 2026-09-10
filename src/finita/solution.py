import autoc.list
import autoc.vector
import autoc.record
import finita.object
import autoc.std as std
from autoc.core import inout


#
class _Solution(finita.object._Traitless, autoc.record.Record):
  
  def __init__(self, field, *args, name=None, **kws):
    self._fields = finita.object.Set(field._decorate_component(("solution", "fields")), field)
    self._entries = autoc.vector.Vector(field._decorate_component(("solution", "entries")), field.entry)
    self._indices = finita.object.Map(field._decorate_component(("solution", "indices")), std.size_t, field.entry)
    super().__init__(name if name else field._decorate_component("solution", abbreviate=False), {
      "fields": self._fields,
      "entries": self._entries,
      "indices": self._indices,
      "finalized": std.int
    })
    self.field = field
    
  def __setup__(self):
    super().__setup__()

    fields = "&target->fields"
    indices = "&target->indices"
    entries = "&target->entries"
    
    with self.method(None, "register", {"target": inout(self), "entry": self.field.entry}) as f:
      f.code = f"""
        size_t index = 0;
        assert(target);
        assert(!target->finalized);
        {self._fields.put(fields, "entry.field")};
        {self._indices.set(indices, f.entry, "index++")};
      """
      
    with self.method(None, "finalize", {"target": inout(self)}) as f:
      r = self._indices.range.variable("r")
      f.code = f"""
        assert(target);
        assert(!target->finalized);
        {self._entries.create_size(entries, self._indices.size(indices))};
        for({r.definition} = {r.type.new(indices)}; !{r.type.empty(r)}; {r.type.move_front(r)}) {{
          {self._entries.set(entries, r.type.front_view(r), r.type.index_front_view(r))};
        }}
        target->finalized = 1;
      """

    with self.method(self.field.entry, "entry", {"target": self, "index": std.size_t}) as f:
      f.inline_code = f"""
        assert(target);
        assert(target->finalized);
        return {self._entries.get(entries, f.index)};
      """
      
    with self.method(std.size_t, "index", {"target": self, "entry": self.field.entry}) as f:
      f.inline_code = f"""
        assert(target);
        assert(target->finalized);
        return {self._indices.get(indices, f.entry)};
      """

    with self.method(std.size_t, "size", {"target": self}) as f:
      f.inline_code = f"""
        assert(target);
        assert(target->finalized);
        return {self._entries.size(entries)};
      """
      
    with self.method(self.field.accessor, "access", {"target": inout(self), "index": std.size_t}) as f:
      f.inline_code = f"""
        assert(target);
        assert(target->finalized);
        return {self.field.entry.access(self._entries.get(entries, f.index))};
      """
      

#
class Solution(finita.object.Object):
  
  def __init__(self, *args, **kws):
    super().__init__(_Solution(*args, **kws))
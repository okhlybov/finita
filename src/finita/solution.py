import metac.vector
import metac.record
import finita.object
import metac.std as std
from metac.core import inout


#
class _Solution(finita.object._Traitless, metac.record.Record):
  
  def __init__(self, field, *args, name=None, **kws):
    self._fields = finita.object.Set(field._decorate_component(("solution", "fields")), field)
    self._entries = metac.vector.Vector(field._decorate_component(("solution", "entries")), field.entry)
    self._indices = finita.object.Map(field._decorate_component(("solution", "indices")), std.size_t, field.entry)
    super().__init__(name if name else field.decorate("Solution"), {
      "fields": self._fields,
      "entries": self._entries,
      "indices": self._indices,
      "finalized": std.int
    }, getters=False, setters=False)
    self.field = field
    
  def __setup__(self):
    super().__setup__()

    fields = "&target->fields"
    indices = "&target->indices"
    entries = "&target->entries"
    
    with self.method(None, "register", {"target": inout(self), "entry": self.field.entry}) as f:
      f.code = f"""
        assert(target);
        assert(!target->finalized);
        size_t index = {self._indices.size(indices)};
        {self._fields.put(fields, "entry.field")};
        {self._indices.set(indices, f.entry, "index")};
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
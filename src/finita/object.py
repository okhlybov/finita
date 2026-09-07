import autoc.core
import autoc.reference
import autoc.intrusive_hash_set
import autoc.intrusive_hash_map


_named = {}


class _Cached(autoc.core._MultiphaseConstructible):
  
  def __call__(cls, *args, **kws):
    obj = super().__call__(*args, **kws)
    if obj.name in _named:
      _obj = _named[obj.name]
      if not (_obj.__class__ == obj.__class__):
        raise TypeError(f"encountered objects of different types")
      return _obj
    else:
      _named[obj.name] = obj
      return obj


# A proxy for shared reference-counted identity-based values
class Object(autoc.reference.Arc, metaclass=_Cached):
  def __init__(self, type, *args, **kws):
    super().__init__(type, *args, **kws)
    self.intrusive_hash_set_kws = dict(
      # Null reference is disallowed
      is_empty=lambda element: f"{element} == ({self})0 /* empty? */",
      mark_empty=lambda element: f"{element} = ({self})0 /* empty! */",
      is_deleted=lambda element: f"{element} == ({self})1 /* deleted? */",
      mark_deleted=lambda element: f"{element} = ({self})1 /* deleted! */",
    )
    
  def __setup__(self):
    super().__setup__()
    # Force identity comparison / hashing
    self.macro_from("hash", lambda target: f"(size_t)&{target}")
    self.macro_from("equal", lambda left, right: f"&{left} == &{right}")
    
    
#
class Set(autoc.intrusive_hash_set.Set):
  
  def __init__(self, name, element, *args, **kws):
    super().__init__(name, element, *args, **element.intrusive_hash_set_kws)


#
class Map(autoc.intrusive_hash_map.Map):
  
  def __init__(self, name, element, index, *args, **kws):
    super().__init__(name, element, index, *args, **index.intrusive_hash_map_kws)
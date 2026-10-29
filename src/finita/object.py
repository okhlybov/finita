import metac.core
import metac.reference
import metac.intrusive_hash_set
import metac.intrusive_hash_map


_named = {}


class _Cached(metac.core._StageConstructorMetaclass):
  
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
class Object(metac.reference.Counted, metaclass=_Cached):
  def __init__(self, type, *args, **kws):
    super().__init__(type, *args, **kws)
    self.sentinel_states = {
      # Null reference is disallowed
      "empty": (
        lambda element: f"{element} == ({self})0 /* empty? */",
        lambda element: f"{element} = ({self})0 /* empty! */",
      ),
      "deleted": (
        lambda element: f"{element} == ({self})1 /* deleted? */",
        lambda element: f"{element} = ({self})1 /* deleted! */",
      ),
    }

  @property
  def in_type(self):
    return self

  @property
  def view_type(self):
    return self
    
  def __setup__(self):
    super().__setup__()
    # Force identity comparison / hashing
    self.macro_from("hash", lambda target: f"(size_t)&{target}")
    self.macro_from("equal", lambda left, right: f"&{left} == &{right}")
    
    
#
class Set(metac.intrusive_hash_set.Set):
  
  def __init__(self, name, element, *args, states=None, **kws):
    if states is None:
      states = element.sentinel_states
    super().__init__(name, element, states, *args, **kws)


#
class Map(metac.intrusive_hash_map.Map):
  
  def __init__(self, name, element, index, *args, states=None, **kws):
    if states is None:
      states = index.sentinel_states
    super().__init__(name, element, index, states, *args, **kws)


# Mark classes intended to be the base type for Object
class _Traitless:

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

  @property
  def moveable(self):
    return False

  @property
  def swappable(self):
    return False
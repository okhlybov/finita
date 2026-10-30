import metac.core
import metac.reference
import metac.intrusive_hash_set
import metac.intrusive_hash_map


_named = {}


class _Cached(metac.core._StageConstructorMetaclass):

  # The name is derived inside the constructor, so a duplicate can only be
  # recognized after it has been constructed - the duplicate is then discarded,
  # keeping the object first registered under the name
  def __call__(cls, *args, **kws):
    obj = super().__call__(*args, **kws)
    if obj.name in _named:
      _obj = _named[obj.name]
      if _obj.__class__ is not obj.__class__:
        raise TypeError(f"the name {obj.name} is already taken by an object of type {_obj.__class__.__name__}")
      if getattr(obj, "_cache_signature", None) != getattr(_obj, "_cache_signature", None):
        raise TypeError(f"the object {obj.name} already exists with a different configuration")
      return _obj
    else:
      _named[obj.name] = obj
      return obj


# A proxy for shared reference-counted identity-based values
class Object(metac.reference.Counted, metaclass=_Cached):

  # The names of the wrapped type's attributes which constitute the
  # configuration - a construction reusing the name of a cached object with a
  # differing configuration is an error rather than a silent cache hit
  _configuration = ()

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

  @property
  def _cache_signature(self):
    return tuple(str(getattr(self.type, name)) for name in self._configuration)

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
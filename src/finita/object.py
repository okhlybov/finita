import autoc.reference
import autoc.intrusive_hash_set


# A proxy for shared reference-counted identity-based values
class Object(autoc.reference.Arc):
  def __init__(self, type, *args, **kws):
    super().__init__(type, *args, **kws)
    self.intrusive_hash_set_kws = dict(
      # Null reference is disallowed
      is_empty=lambda element: f"{element} == ({self})(size_t)0 /* empty? */",
      mark_empty=lambda element: f"{element} = ({self})(size_t)0 /* empty! */",
      is_deleted=lambda element: f"{element} == ({self})(size_t)1 /* deleted? */",
      mark_deleted=lambda element: f"{element} = ({self})(size_t)1 /* deleted! */",
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
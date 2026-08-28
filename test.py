import sys
sys.path.insert(0, "src")
sys.path.insert(0, "../autoc/src")
import autoc.std as std


from pathlib import Path


import autoc.module
import autoc.cmake


from finita.cartesian2 import grid

from finita.field import field

with autoc.module.Module(sys.argv[1], stateful=False) as m:
  m.add(field(std.float, grid))

autoc.cmake.CMake(m)

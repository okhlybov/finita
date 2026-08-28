import sys
sys.path.insert(0, "src")
sys.path.insert(0, "../autoc/src")


from pathlib import Path


import autoc.module
import autoc.cmake


import finita.cartesian2

n = finita.cartesian2.node_t

from autoc.vector import *

from finita.field import *

with autoc.module.Module(sys.argv[1], stateful=False) as m:
  m.add(Field(std.double, finita.cartesian2.grid_t))
  
  m.add(Vector("NV", n))

autoc.cmake.CMake(m)

import sys
sys.path.insert(0, "src")
sys.path.insert(0, "../autoc/src")
import autoc.std as std


from finita.module import Module
from finita.problem import Problem

from finita.cartesian2 import Mesh

from finita.field import Field

F = Field(std.complex, Mesh())

with Module("test", stateful=False) as m:
  with Problem("Test"):
    M = Mesh().instance("M")
    T = F.instance("T")

import autoc.cmake
autoc.cmake.CMake(m)
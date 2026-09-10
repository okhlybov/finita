import sys
sys.path.insert(0, "src")
sys.path.insert(0, "../autoc/src")
import autoc.std as std


from finita.module import *
from finita.problem import *

from finita.cartesian2 import Mesh

from finita.field import Field

from finita.solution import Solution


with Module("test", stateful=False) as m:
  F = Field("long double", Mesh())
  with Problem("Test"):
    Nx = int("Nx", value=-1)
    Ny = int("Ny")
    Ra = double("Ra", value=1e5)
    M = Mesh().instance("M").create((0,-10), (Nx,Ny))
    T = F.instance("T").create(M)
    #m.add(finita.solution.Builder(F))
    m.add(Solution(F))

import autoc.cmake
autoc.cmake.CMake(m)
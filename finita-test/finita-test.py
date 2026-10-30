import metac.std as std
import metac

from finita.module import *
from finita.problem import *

from finita.cartesian2 import Mesh

from finita.field import Field

from finita.solution import Solution

with metac.builder(default="cmake"):
  with finita.module(default="finita-test", stateful=False) as m:
    F = Field(std.long_double, Mesh())
    with Problem("Test"):
      Nx = int("Nx", value=33)
      Ny = int("Ny", value=33)
      Ra = double("Ra", value=1e5)
      M = Mesh().instance("M").create((0,-10), (Nx,Ny))
      T = F.instance("T").create(M, layers=3)
      #m.add(finita.solution.Builder(F))
      m.add(Solution(F))
      print(F.entry.equal.signature)
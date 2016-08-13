$: << "lib"; require "finita/common"
Gem::Specification.new do |spec|
  spec.name = "finita"
  spec.version = Finita::Version
  spec.author = "Oleg A. Khlybov"
  spec.email = "fougas@mail.ru"
  spec.license = "BSD-2-Clause"
  spec.homepage = "http://finita.sourceforge.net/"
  spec.summary = "Package for solving complex PDE/algebraic systems of equations numerically using grid methods"
  spec.required_ruby_version = Gem::Requirement.new(">= 1.9")
  spec.executables = ["finitac"]
  spec.files = Dir["bin/finitac"] + Dir["lib/**/*.rb"] + [:bratu, :cavity, :rmf].collect{|p| Dir["sample/#{p}.{c,rb}"]}.flatten
  spec.add_runtime_dependency("autoc", "~> 1.3")
  spec.description = <<-EOF
    Finita is a software package intended for solving complex systems of differential and algebraic equations numerically
    using grid methods in a manner of FreeFEM++ and FlexPDE systems but, instead of solving problems directly,
    it acts as a code generator which emits the plain C source code for the program which performs the actual computations.
    The supported PDE discretization methods include finite difference and finite volume methods on regular grids.
    Finita can generate either sequential or parallel code (threaded and MPI) and takes advantage of a few well-known
    (non)linear solvers such as PETSc, MUMPS, SuperLU etc.
  EOF
end
require 'finita/common'
require 'finita/system'


module Finita


class Equation

  attr_reader :lhs, :unknown, :domain, :system

  def initialize(lhs, unknown, domain, system = Finita::System.object)
    @lhs = lhs
    @unknown = unknown
    @system = system
    @domain = domain
    system.equations << self
  end

  def bind(gtor)
    unknown.bind(gtor)
  end

end # Equation


end # Finita
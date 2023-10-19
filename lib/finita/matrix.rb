require 'autoc/record'
require 'finita/core'


module Finita::Matrix


  # Type representing the matrix index which consists of row/column node pair
  class RC < AutoC::Record

    def initialize(node, **kws) = super(node.decorate(:_RC), { row: node, column: node }, profile: :glassbox, visibility: :internal, **kws)
  
  end # RC


end
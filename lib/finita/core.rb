# frozen_string_literal: true


require 'autoc/composite'
require 'autoc/structure'


module Finita

  
  module Pristine
    def default_constructible? = false
    def custom_constructible? = false
    def destructible? = false
    def comparable? = false
    def orderable? = false
    def hashable? = false
    def copyable? = false
  end


end
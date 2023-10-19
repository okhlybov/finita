# frozen_string_literal: true


require 'autoc/type'
require 'autoc/module'
require 'autoc/decorator'
require 'autoc/record'


module Finita


  # @abstract
  # Base class for value types
  class Value < AutoC::Type

    include AutoC::Entity

    include AutoC::Decorator

    def prefix = signature

    def to_value = rvalue

    def rvalue = @rv ||= AutoC::Value.new(self)

    def lvalue = @lv ||= AutoC::Value.new(self, reference: true)

    def const_rvalue = @crv ||= AutoC::Value.new(self, constant: true)

    def const_lvalue = @clv ||= AutoC::Value.new(self, constant: true, reference: true)


    def initialize(*args, **kws)
      super
      dependencies << AutoC::Module::DEFINITIONS
    end

  end # Value


end

# frozen_string_literal: true


require 'autoc/stdc'
require 'autoc/module'
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


  module Instantiable
    @@count = 0
    def instance(identifier = "_finita#{@@count+=1}_", visibility: :public) = Instance.new(self, identifier, visibility:)
  end


  class Node < AutoC::Structure
    attr_reader :items
    def initialize(type, items)
      @items = items
      super type, ::Hash[items.collect{ |_| [_, :int] }], profile: :glassbox
    end
  end


  #
  class Instantiable::Instance

    include AutoC::Entity

    attr_reader :type

    attr_reader :identifier

    attr_reader :visibility

    def to_s = identifier.to_s

    def initialize(type, identifier, visibility: :public)
      dependencies << @type = type
      @identifier = identifier
      @visibility = visibility
    end

    def method_missing(meth, *args)
      args.unshift(identifier)
      args.each { |x| dependencies << x if x.is_a?(AutoC::Entity) }
      @setup_code = type.send(meth, *args)
      self
    end

    def interface_definitions(stream)
      instance_definitions(stream) if visibility == :public
    end

    def forward_declarations(stream)
      instance_definitions(stream) unless visibility == :public
    end

    private def instance_definitions(stream)
      stream << "AUTOC_EXTERN #{type.type} #{identifier};"
    end

    def definitions(stream)
      stream << "#{type.type} #{identifier};"
    end

    def setup(stream)
      stream << "#{@setup_code};" if !@setup_code.nil?
    end

    def cleanup(stream)
      stream << "#{type.destroy(identifier)};" if type.destructible? && !@setup_code.nil?
    end

  end


end
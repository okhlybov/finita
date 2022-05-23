# frozen_string_literal: true


require 'autoc/module'
require 'autoc/composite'


module Finita

  
  class Module < AutoC::Module

    def initialize(*args, **kws)
      super
      self << @code = Code.new(self)
    end

    def self.render(name, &code)
      m = Module.new(name)
      yield(m) if block_given?
      m.render
    end

    private def total_entities
      @total_entities ||= begin
        (set = super).each do |e|
          @code.setup_entities << e if e.respond_to?(:setup)
          @code.cleanup_entities << e if e.respond_to?(:cleanup)
        end
        set
      end
    end

  end


  class Module::Code

    include AutoC::Entity

    private def setup = @setup ||= "#{@module.name}Setup"
    private def cleanup = @cleanup ||= "#{@module.name}Cleanup"

    attr_reader :setup_entities
    attr_reader :cleanup_entities

    def initialize(m)
      @module  = m
      @setup_entities = []
      @cleanup_entities = []
      dependencies << Module::DEFINITIONS << Module::INCLUDES
    end

    def interface_declarations(stream)
      stream << %{
        /**
          @brief #{@module.name} module initializer
        */
        AUTOC_EXTERN void #{setup}(void);
        /**
          @brief #{@module.name} module finalizer
        */
        AUTOC_EXTERN void #{cleanup}(void);
      }
    end

    def definitions(stream)
      stream << %{
        static int #{@module.name}Live = 0;
      }
      stream << "void #{setup}() { if(!#{@module.name}Live) {"
        @setup_entities.sort.each { |e| e.setup(stream) }
      stream << "#{@module.name}Live = 1;}}"
      stream << "void #{cleanup}() { if(#{@module.name}Live) {"
        @cleanup_entities.sort.reverse_each { |e| e.cleanup(stream) }
      stream << "#{@module.name}Live = 0;}}"
    end

  end


end
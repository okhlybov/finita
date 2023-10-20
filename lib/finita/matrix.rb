# frozen_string_literal: true


require 'finita/core'
require 'autoc/record'
require 'autoc/intrusive_hash_set'
require 'autoc/intrusive_hash_map'


module Finita::Matrix


  # Type representing the matrix index which consists of row/column node pair
  class RC < AutoC::Record

    def initialize(node, **kws) = super(node.decorate(:_RC), { row: node, column: node }, profile: :glassbox, visibility: :private, **kws)

  end # RC


  class NodeSet < AutoC::IntrusiveHashSet

    def configure
      super
      dependencies << AutoC::STD::LIMITS_H
      tag_empty.inline_code %{slot->element.field = USHRT_MAX;}
      is_empty.inline_code %{return slot->element.field == USHRT_MAX;}
      tag_deleted.inline_code %{slot->element.field = USHRT_MAX-1;}
      is_deleted.inline_code %{return slot->element.field == USHRT_MAX-1;}
    end

  end # NodeSet


  class Matrix < AutoC::IntrusiveHashMap

    attr_reader :node

    def initialize(type, node, **kws)
      super(type, :int, (@node = node).rc, **kws)
    end

    def configure
      super
      dependencies << AutoC::STD::LIMITS_H
      method(:void, :merge, { target: lvalue, row: node.const_rvalue, column: node.const_rvalue, value: :int }).configure do
        code %{
          #{node.rc} node;
          #{node.rc.create_set}(&node, row, column);
          #{set}(target, &node, value);
        }
      end
      tag_empty.inline_code %{slot->index.row.field = USHRT_MAX;}
      is_empty.inline_code %{return slot->index.row.field == USHRT_MAX;}
      tag_deleted.inline_code %{slot->index.row.field = USHRT_MAX-1;}
      is_deleted.inline_code %{return slot->index.row.field == USHRT_MAX-1;}
    end

  end # Matrix


end

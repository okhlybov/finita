require 'finita/common'


module Finita::Ordering


class StaticCode < Finita::StaticCodeTemplate
  TAG = :FinitaOrdering
  def entities; super + [Finita::Generator::StaticCode.instance, Finita::NodeMapCode.instance] end
  def write_intf(stream)
    stream << %$
      typedef struct {
        FinitaNodeMap map;
        FinitaNode* linear;
        int linear_size;
        int frozen;
      } #{TAG};
      void #{TAG}Ctor(#{TAG}* self, int node_count);
      int #{TAG}Put(#{TAG}* self, FinitaNode node);
      int #{TAG}Index(#{TAG}* self, FinitaNode node);
      FinitaNode #{TAG}Node(#{TAG}* self, int index);
      int #{TAG}Size(#{TAG}* self);
    $
  end
  def write_defs(stream)
    stream << %$
      void #{TAG}Ctor(#{TAG}* self, int node_count) {
        FINITA_ASSERT(self);
        self->frozen = 0;
        FinitaNodeMapCtor(&self->map, node_count);
      }
      int #{TAG}Put(#{TAG}* self, FinitaNode node) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(!self->frozen);
        if(!FinitaNodeMapContainsKey(&self->map, node)) {
          FinitaNodeMapPut(&self->map, node, -1);
          return 1;
        } else {
          return 0;
        }
      }
      void #{TAG}Freeze(#{TAG}* self) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(!self->frozen);
        self->frozen = 1;
      }
      int #{TAG}Index(#{TAG}* self, FinitaNode node) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(self->frozen);
        FINITA_ASSERT(FinitaNodeMapContainsKey(&self->map, node));
        return FinitaNodeMapGet(&self->map, node);
      }
      FinitaNode #{TAG}Node(#{TAG}* self, int index) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(self->frozen);
        FINITA_ASSERT(0 <= index && index < #{TAG}Size(self));
        return self->linear[index];
      }
      int #{TAG}Size(#{TAG}* self) {
        FINITA_ASSERT(self);
        return FinitaNodeMapSize(&self->map);
      }
    $
  end
  def source_size
    str = String.new
    write_defs(str)
    str.size
  end
end # StaticCode


class Naive
  TAG = :FinitaNaiveOrdering
  class StaticCode < Finita::StaticCodeTemplate
    def entities; super + [Ordering::StaticCode.instance] end
    def write_intf(stream)
      stream << "void #{TAG}Freeze(FinitaOrdering*);"
    end
    def write_defs(stream)
      stream << %$
        void #{TAG}Freeze(FinitaOrdering* self) {
          int index;
          FinitaNodeMapIt it;
          FINITA_ASSERT(self);
          FINITA_ASSERT(!self->frozen);
          self->linear_size = FinitaNodeMapSize(&self->map);
          self->linear = (FinitaNode*)malloc(sizeof(FinitaNode)*self->linear_size); FINITA_ASSERT(self->linear);
          FinitaNodeMapItCtor(&it, &self->map);
          index = 0;
          while(FinitaNodeMapItHasNext(&it)) {
            self->linear[index++] = FinitaNodeMapItNextKey(&it);
          }
          FINITA_ASSERT(index == self->linear_size);
          for(index = 0; index < self->linear_size; ++index) {
            FinitaNodeMapPutForce(&self->map, self->linear[index], index);
          }
          self->frozen = 1;
        }
      $
    end
    def source_size
      str = String.new
      write_defs(str)
      str.size
    end
  end # StaticCode
  class Code < Finita::BoundCodeTemplate
    def entities; super + [StaticCode.instance] end
    def freeze; "#{TAG}Freeze" end
  end # Code
  def bind(gtor)
    Code.new(self, gtor) unless gtor.bound?(self)
  end
end # Naive


end # Ordering
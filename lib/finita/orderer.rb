require 'finita/common'


module Finita::Orderer


class StaticCode < Finita::StaticCodeTemplate
  TAG = :FinitaOrderer
  def entities; super + [Finita::NodeMapCode.instance] end
  def write_intf(stream)
    stream << %$
      typedef struct {
        FinitaNodeMap map;
        FinitaNode* linear;
        int linear_size;
        int frozen;
      } #{TAG};
      void #{TAG}Ctor(#{TAG}* self, int node_count);
      void #{TAG}Merge(#{TAG}* self, FinitaNode node);
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
      void #{TAG}Merge(#{TAG}* self, FinitaNode node) {
        FINITA_ASSERT(self);
        FINITA_ASSERT(!self->frozen);
        FinitaNodeMapPutForce(&self->map, node, -1);
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
        FINITA_ASSERT(self->frozen);
        return self->linear_size;
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
  TAG = :FinitaNaiveOrderer
  class StaticCode < Finita::StaticCodeTemplate
    def entities; super + [Orderer::StaticCode.instance] end
    def write_intf(stream)
      stream << "void #{TAG}Freeze(FinitaOrderer*);"
    end
    def write_defs(stream)
      stream << %$
        void #{TAG}Freeze(FinitaOrderer* self) {
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
  end # StaticCode
  class Code < Finita::BoundCodeTemplate
    attr_reader :name
    def entities; super + [StaticCode.instance] end
    def initialize(orderer, gtor, system)
      super({:orderer=>orderer}, gtor)
      @system = system
      @name = system.name
    end
    def write_intf(stream)
      stream << %$
        extern FinitaOrderer #{name}Orderer;
        void #{name}OrdererSetup();
      $
    end
    def write_defs(stream)
      stream << %$
        extern int #{name}ApproxNodeCount();
        extern void #{name}CollectNodes();
        FinitaOrderer #{name}Orderer;
        void #{name}OrdererSetup() {
          FinitaOrdererCtor(&#{name}Orderer, #{name}ApproxNodeCount());
          #{name}CollectNodes();
          #{TAG}Freeze(&#{name}Orderer);
        }
      $
    end
  end # Code

  def bind(gtor, system)
    Code.new(self, gtor, system) unless gtor.bound?(self)
  end

end # Naive


end # Orderer
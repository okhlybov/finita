require 'finita/common'


module Finita::Mapper


class StaticCode < Finita::StaticCodeTemplate
  TAG = :FinitaMapper
  def entities; super + [Finita::NodeMapCode.instance] end
  def write_intf(stream)
    stream << %$
      typedef struct #{TAG} #{TAG};
      void #{TAG}Ctor(#{TAG}*, int);
      void #{TAG}Merge(#{TAG}*, FinitaNode);
      int #{TAG}Index(#{TAG}*, FinitaNode);
      FinitaNode #{TAG}Node(#{TAG}*, int);
      int #{TAG}Size(#{TAG}*);
    $
  end
  def write_defs(stream)
    stream << %$
      struct #{TAG} {
        FinitaNodeMap map;
        FinitaNode* linear;
        int linear_size;
        int frozen;
      };
      void #{TAG}Ctor(#{TAG}* self, int size) {
        FINITA_ASSERT(self);
        self->frozen = 0;
        FinitaNodeMapCtor(&self->map, size);
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
  TAG = :FinitaNaiveMapper
  class StaticCode < Finita::StaticCodeTemplate
    def entities; super + [Mapper::StaticCode.instance] end
    def write_defs(stream)
      stream << %$
        static void #{TAG}Freeze(FinitaMapper* self) {
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
    def entities; super + [NodeSetCode.instance, StaticCode.instance] end
    def initialize(mapper, gtor, system)
      super({:mapper=>mapper}, gtor)
      @system = system
      @name = system.name
    end
    def write_intf(stream)
      stream << %$
        extern FinitaMapper #{name}Mapper;
        void #{name}SetupMapper(FinitaNodeSet*);
      $
    end
    def write_defs(stream)
      stream << %$
        FinitaMapper #{name}Mapper;
        void #{name}SetupMapper(FinitaNodeSet* nodes) {
          FinitaNodeSetIt it;
          FinitaMapperCtor(&#{name}Mapper, FinitaNodeSetSize(nodes));
          FinitaNodeSetItCtor(&it, nodes);
          while(FinitaNodeSetItHasNext(&it)) {
            FinitaMapperMerge(&#{name}Mapper, FinitaNodeSetItNext(&it));
          }
          #{TAG}Freeze(&#{name}Mapper);
        }
      $
    end
  end # Code

  def bind(gtor, system)
    Code.new(self, gtor, system) unless gtor.bound?(self)
  end

end # Naive


end # Mapper
require 'singleton'
require 'code_builder'


module CDataStruct


class Type

  class StaticCode
    include Singleton
    def entities; [] end
    def source_size; 0 end
    def attach(source) end
    def priority; CodeBuilder::Priority::DEFAULT end
    def write_intf(stream)
      stream << """
        #include <assert.h>
        #include <malloc.h>
        #include <stdlib.h>
      """
    end
    def write_defs(stream) end
    def write_decls(stream) end
  end # StaticCode

  def malloc; :malloc end
  def assert; :assert end
  def abort; :abort end
  attr_reader :type, :visible
  def initialize(type, visible = true)
    @type = type
    @visible = visible
  end
  def attach(source) source << self if source.smallest? end
  def entities; [StaticCode.instance] end
  def priority
    result = CodeBuilder::Priority::DEFAULT
    entities.each {|e| result = e.priority if result > e.priority}
    result
  end
  def source_size
    stream = String.new
    write_defs(stream)
    stream.size
  end
  def write_intf(stream) write_intf_real(stream) if visible end
  def write_decls(stream) write_intf_real(stream) unless visible end
end


class List < Type
  
  attr_reader :element_type
  
  def node; "#{type}Node" end

  def it; "#{type}It" end
    
  def ctor; "#{type}Ctor" end
    
  def first; "#{type}First" end
    
  def last; "#{type}Last" end
    
  def append; "#{type}Append" end
  
  def prepend; "#{type}Prepend" end
    
  def size; "#{type}Size" end
    
  def empty; "#{type}Empty" end
    
  def it_ctor; "#{type}ItCtor" end
    
  def it_has_next; "#{type}ItHasNext" end
  
  def it_next; "#{type}ItNext" end
      
  def initialize(type, element_type, visible = true)
    super(type, visible)
    @element_type = element_type
  end
  
  def write_intf_real(stream)
    stream << """
        typedef struct #{node}_ #{node};
        struct #{node}_ {
            #{element_type} element;
            #{node}* next_node;
        };
        typedef struct {
            #{node}* head_node;
            #{node}* tail_node;
            int node_count;
        } #{type};
        typedef struct {
            #{node}* next_node;
        } #{it};
        void #{ctor}(#{type}*);
        #{element_type} #{first}(#{type}*);
        #{element_type} #{last}(#{type}*);
        void #{append}(#{type}*, #{element_type});
        void #{prepend}(#{type}*, #{element_type});
        int #{size}(#{type}*);
        int #{empty}(#{type}*);
        void #{it_ctor}(#{it}*, #{type}*);
        int #{it_has_next}(#{it}*);
        #{element_type} #{it_next}(#{it}*);
    """
  end
  
  def write_defs(stream)
    stream << """
        void #{ctor}(#{type}* self) {
            #{assert}(self);
            self->head_node = self->tail_node = NULL;
            self->node_count = 0;
        }
        #{element_type} #{first}(#{type}* self) {
            #{assert}(self);
            return self->head_node->element;
        }
        #{element_type} #{last}(#{type}* self) {
            #{assert}(self);
            return self->tail_node->element;
        }
        void #{append}(#{type}* self, #{element_type} element) {
            #{node}* node;
            #{assert}(self);
            node = (#{node}*) #{malloc}(sizeof(#{node})); #{assert}(node);
            node->element = element;
            node->next_node = NULL;
            if(self->tail_node) self->tail_node->next_node = node;
            self->tail_node = node;
            if(!self->head_node) self->head_node = self->tail_node;
            ++self->node_count;
        }
        void #{prepend}(#{type}* self, #{element_type} element) {
            #{node}* node;
            #{assert}(self);
            node = (#{node}*) #{malloc}(sizeof(#{node})); #{assert}(node);
            node->element = element;
            node->next_node = self->head_node;
            self->head_node = node;
            if(!self->tail_node) self->tail_node = node;
            ++self->node_count;
        }
        int #{size}(#{type}* self) {
            #{assert}(self);
            return self->node_count;
        }
        int #{empty}(#{type}* self) {
            #{assert}(self);
            return !self->node_count;
        }
        void #{it_ctor}(#{it}* self, #{type}* list) {
            #{assert}(self);
            #{assert}(list);
            self->next_node = list->head_node;
        }
        int #{it_has_next}(#{it}* self) {
            #{assert}(self);
            return self->next_node != NULL;
        }
        #{element_type} #{it_next}(#{it}* self) {
            #{node}* node;
            #{assert}(self);
            node = self->next_node;
            self->next_node = self->next_node->next_node;
            return node->element;
        }
    """
  end

end # List


class Set < Type

  attr_reader :element_type, :hasher, :comparator

  def ctor; "#{type}Ctor" end

  def contains; "#{type}Contains" end

  def get; "#{type}Get" end

  def put; "#{type}Put" end

  def size; "#{type}Size" end

  def empty; "#{type}Empty" end

  def it; "#{type}It" end

  def it_ctor; "#{type}ItCtor" end

  def it_has_next; "#{type}ItHasNext" end

  def it_next; "#{type}ItNext" end

  def initialize(type, element_type, hasher, comparator, visible = true)
    super(type, visible)
    @element_type = element_type
    @hasher = hasher
    @comparator = comparator
    @bucket = new_bucket_list
  end

  def new_bucket_list
    List.new("#{type}Bucket", element_type, visible)
  end

  def write_intf_real(stream)
    bucket.write_intf_real(stream)
    stream << """
        typedef struct {
            #{bucket.type}* buckets;
            int bucket_count;
          int size;
        } #{type};
        typedef struct {
          #{type}* set;
          int bucket_index;
          #{bucket.it} it;
        } #{it};
        extern int #{hasher}(#{element_type});
        extern int #{comparator}(#{element_type}, #{element_type});
        void #{ctor}(#{type}*, int);
        int #{contains}(#{type}*, #{element_type});
        #{element_type} #{get}(#{type}*, #{element_type});
        int #{size}(#{type}*);
        int #{empty}(#{type}*);
        int #{put}(#{type}*, #{element_type});
        void #{it_ctor}(#{it}*, #{type}*);
        int #{it_has_next}(#{it}*);
        #{element_type} #{it_next}(#{it}*);
    """
  end

  def write_defs(stream)
    bucket.write_defs(stream)
    stream << """
        void #{ctor}(#{type}* self, int bucket_count) {
            int i;
            #{assert}(self);
            #{assert}(bucket_count > 0);
            self->buckets = (#{bucket.type}*) #{malloc}(bucket_count*sizeof(#{bucket.type})); #{assert}(self->buckets);
            for(i = 0; i < bucket_count; ++i) {
                #{bucket.ctor}(&self->buckets[i]);
            }
            self->bucket_count = bucket_count;
          self->size = 0;
        }
        int #{contains}(#{type}* self, #{element_type} element) {
          #{bucket.type}* bucket;
            #{bucket.it} it;
            #{assert}(self);
          bucket = &self->buckets[abs(#{hasher}(element) % self->bucket_count)];
            #{bucket.it_ctor}(&it, bucket);
            while(#{bucket.it_has_next}(&it)) {
                if(#{comparator}(element, #{bucket.it_next}(&it))) {
                    return 1;
                }
            }
            return 0;
        }
        #{element_type} #{get}(#{type}* self, #{element_type} element) {
          #{bucket.type}* bucket;
            #{bucket.it} it;
            #{assert}(self);
            #{assert}(#{contains}(self, element));
          bucket = &self->buckets[abs(#{hasher}(element) % self->bucket_count)];
            #{bucket.it_ctor}(&it, bucket);
            while(#{bucket.it_has_next}(&it)) {
                #{element_type} e = #{bucket.it_next}(&it);
                if(#{comparator}(element, e)) {
                    return e;
                }
            }
            #{abort}(); return element; /* Must not reach this point */
        }
        int #{size}(#{type}* self) {
            #{assert}(self);
            return self->size;
        }
        int #{empty}(#{type}* self) {
            #{assert}(self);
            return !self->size;
        }
        int #{put}(#{type}* self, #{element_type} element) {
          #{bucket.type}* bucket;
          #{bucket.it} it;
          #{assert}(self);
          bucket = &self->buckets[abs(#{hasher}(element) % self->bucket_count)];
            #{bucket.it_ctor}(&it, bucket);
            while(#{bucket.it_has_next}(&it)) {
                if(#{comparator}(element, #{bucket.it_next}(&it))) {
                    return 0;
                }
            }
          #{bucket.append}(bucket, element);
          ++self->size;
            return 1;
        }
        void #{it_ctor}(#{it}* self, #{type}* set) {
          #{assert}(self);
          self->set = set;
          self->bucket_index = 0;
          #{bucket.it_ctor}(&self->it, &set->buckets[0]);
        }
        int #{it_has_next}(#{it}* self) {
          #{assert}(self);
          if(#{bucket.it_has_next}(&self->it)) {
            return 1;
          } else {
            int i; for(i = self->bucket_index+1; i < self->set->bucket_count; ++i) {
              if(!#{bucket.empty}(&self->set->buckets[i])) {
                return 1;
              }
            }
            return 0;
          }
        }
        #{element_type} #{it_next}(#{it}* self) {
          #{assert}(self);
          #{assert}(#{it_has_next}(self));
          if(#{bucket.it_has_next}(&self->it)) {
            return #{bucket.it_next}(&self->it);
          } else {
            int i; for(i = self->bucket_index+1; i < self->set->bucket_count; ++i) {
              if(!#{bucket.empty}(&self->set->buckets[i])) {
                #{bucket.it_ctor}(&self->it, &self->set->buckets[i]);
                self->bucket_index = i;
                return #{bucket.it_next}(&self->it);
              }
            }
            #{abort}(); return #{bucket.it_next}(&self->it); /* Must not reach this point */
          }
      }
    """
  end

  protected

  attr_reader :bucket

end # Set


class Map < Type

  attr_reader :key_type, :value_type, :hasher, :comparator

  def pair; "#{type}Pair" end

  def ctor; "#{type}Ctor" end

  def contains_key; "#{type}ContainsKey" end

  def get; "#{type}Get" end

  def put; "#{type}Put" end

  def size; "#{type}Size" end

  def empty; "#{type}Empty" end

  def it; "#{type}It" end

  def it_ctor; "#{type}ItCtor" end

  def it_has_next; "#{type}ItHasNext" end

  def it_next_key; "#{type}ItNextKey" end

  def it_next_value; "#{type}ItNextValue" end

  def initialize(type, key_type, value_type, hasher, comparator, visible = true)
    super(type, visible)
    @key_type = key_type
    @value_type = value_type
    @hasher = hasher
    @comparator = comparator
    @pair_set = new_pair_set
  end

  def new_pair_set
    Set.new("#{type}PairSet", "#{type}Pair", "#{type}PairHasher", "#{type}PairComparator", visible)
  end

  def write_intf_real(stream)
    stream << """
        typedef struct {
            #{key_type} key;
            #{value_type} value;
        } #{pair};
    """
    pair_set.write_intf_real(stream)
    stream << """
        typedef struct {
            #{pair_set.type} pairs;
        } #{type};
        typedef struct {
            #{pair_set.it} it;
        } #{it};
        extern int #{hasher}(#{key_type});
        extern int #{comparator}(#{key_type}, #{key_type});
        void #{ctor}(#{type}*, int);
        int #{size}(#{type}*);
        int #{contains_key}(#{type}*, #{key_type});
        #{value_type} #{get}(#{type}*, #{key_type});
        int #{put}(#{type}*, #{key_type}, #{value_type});
        void #{it_ctor}(#{it}*, #{type}*);
        int #{it_has_next}(#{it}*);
        #{key_type} #{it_next_key}(#{it}*);
        #{value_type} #{it_next_value}(#{it}*);
    """
  end

  def write_defs(stream)
    pair_set.write_defs(stream)
    stream << """
        int #{pair_set.hasher}(#{pair} pair) {
            return #{hasher}(pair.key);
        }
        int #{pair_set.comparator}(#{pair} lt, #{pair} rt) {
            return #{comparator}(lt.key, rt.key);
        }
        void #{ctor}(#{type}* self, int bucket_count) {
            #{assert}(self);
            #{pair_set.ctor}(&self->pairs, bucket_count);
        }
        int #{size}(#{type}* self) {
            return #{pair_set.size}(&self->pairs);
        }
        int #{contains_key}(#{type}* self, #{key_type} key) {
          #{pair} pair;
          #{assert}(self);
          pair.key = key;
          return #{pair_set.contains}(&self->pairs, pair);
        }
        #{value_type} #{get}(#{type}* self, #{key_type} key) {
          #{pair} pair;
          #{assert}(self);
          #{assert}(#{contains_key}(self, key));
          pair.key = key;
          return #{pair_set.get}(&self->pairs, pair).value;
        }
        int #{put}(#{type}* self, #{key_type} key, #{value_type} value) {
            #{assert}(self);
            if(!#{contains_key}(self, key)) {
              int result;
              #{pair} pair;
              pair.key = key;
              pair.value = value;
              result = #{pair_set.put}(&self->pairs, pair); #{assert}(result);
              return 1;
            } else {
              return 0;
            }
        }
        void #{it_ctor}(#{it}* self, #{type}* map) {
            #{assert}(self);
            #{assert}(map);
            #{pair_set.it_ctor}(&self->it, &map->pairs);
        }
        int #{it_has_next}(#{it}* self) {
            #{assert}(self);
            return #{pair_set.it_has_next}(&self->it);
        }
        #{key_type} #{it_next_key}(#{it}* self) {
            #{assert}(self);
            return #{pair_set.it_next}(&self->it).key;
        }
        #{value_type} #{it_next_value}(#{it}* self) {
            #{assert}(self);
            return #{pair_set.it_next}(&self->it).value;
        }
    """
  end

  protected

  attr_reader :pair_set

end # Map


end
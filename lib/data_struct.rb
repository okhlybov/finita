require 'singleton'
require 'code_builder'


module DataStruct


class Prologue < CodeBuilder::Code
  include Singleton
  def write_intf(stream)
    stream << %$
      #include <stddef.h>
      #include <assert.h>
      #include <stdlib.h>
      #include <malloc.h>
    $
  end
end # Prologue


class Struct < CodeBuilder::Code
  undef abort;
  attr_reader :type, :elementType
  def initialize(type, element_type)
    @overrides = {:malloc=>'malloc', :calloc=>'calloc', :assert=>'assert', :abort=>'abort'}
    @type = type
    @elementType = element_type
  end
  def entities; [Prologue.instance] end
  def method_missing(method, *args)
    if @overrides.include?(method)
      @overrides[method]
    else
      s = method.to_s
      @type + s[0].capitalize + s[1..-1]
    end
  end
end # Struct


class Array < Struct
  def write_intf(stream)
    stream << %$
      typedef struct #{type} #{type};
      typedef struct #{it} #{it};
      struct #{type} {
        #{elementType}* values;
        size_t element_count;
      };
      struct #{it} {
        #{type}* array;
        size_t index;
      };
      void #{ctor}(#{type}*, size_t);
      #{type}* #{new}(size_t);
      #{elementType} #{get}(#{type}*, size_t);
      void #{set}(#{type}*, size_t, #{elementType});
      int #{within}(#{type}*, size_t);
      size_t #{size}(#{type}*);
      void #{itCtor}(#{it}*, #{type}*);
      int #{itHasNext}(#{it}*);
      #{elementType} #{itNext}(#{it}*);
    $
  end
  def write_defs(stream)
    stream << %$
      void #{ctor}(#{type}* self, size_t element_count) {
        #{assert}(self);
        #{assert}(element_count > 0);
        self->element_count = element_count;
        self->values = (#{elementType}*) #{calloc}(element_count, sizeof(#{elementType})); #{assert}(self->values);
      }
      #{type}* #{new}(size_t element_count) {
        #{type}* self = (#{type}*)#{malloc}(sizeof(#{type})); #{assert}(self);
        #{ctor}(self, element_count);
        return self;
      }
      #{elementType} #{get}(#{type}* self, size_t index) {
        #{assert}(self);
        #{assert}(#{within}(self, index));
        return self->values[index];
      }
      void #{set}(#{type}* self, size_t index, #{elementType} value) {
        #{assert}(self);
        #{assert}(#{within}(self, index));
        self->values[index] = value;
      }
      int #{within}(#{type}* self, size_t index) {
        #{assert}(self);
        return index < self->element_count;
      }
      size_t #{size}(#{type}* self) {
        #{assert}(self);
        return self->element_count;
      }
      void #{itCtor}(#{it}* self, #{type}* array) {
        #{assert}(self);
        #{assert}(array);
        self->array = array;
        self->index = 0;
      }
      int #{itHasNext}(#{it}* self) {
        #{assert}(self);
        return self->index < #{size}(self->array);
      }
      #{elementType} #{itNext}(#{it}* self) {
        #{assert}(self);
        return #{get}(self->array, self->index++);
      }
    $
  end
end # Array


class List < Struct
  attr_reader :comparator
  def initialize(type, element_type, comparator)
    super(type, element_type)
    @comparator = comparator
  end
  def write_intf(stream)
    stream << %$
      typedef struct #{node} #{node};
      typedef struct #{type} #{type};
      typedef struct #{it} #{it};
      struct #{type} {
        #{node}* head_node;
        #{node}* tail_node;
        size_t node_count;
      };
      struct #{it} {
        #{node}* next_node;
      };
      void #{ctor}(#{type}*);
      #{type}* #{new}(void);
      #{elementType} #{first}(#{type}*);
      #{elementType} #{last}(#{type}*);
      void #{append}(#{type}*, #{elementType});
      void #{prepend}(#{type}*, #{elementType});
      int #{contains}(#{type}*, #{elementType});
      #{elementType} #{get}(#{type}*, #{elementType});
      int #{replace}(#{type}*, #{elementType}, #{elementType});
      int #{replaceAll}(#{type}*, #{elementType}, #{elementType});
      size_t #{size}(#{type}*);
      int #{empty}(#{type}*);
      void #{itCtor}(#{it}*, #{type}*);
      int #{itHasNext}(#{it}*);
      #{elementType} #{itNext}(#{it}*);
    $
  end
  def write_defs(stream)
    stream << %$
      struct #{node} {
        #{elementType} element;
        #{node}* next_node;
      };
      extern int #{comparator}(#{elementType}, #{elementType});
      void #{ctor}(#{type}* self) {
        #{assert}(self);
        self->head_node = self->tail_node = NULL;
        self->node_count = 0;
      }
      #{type}* #{new}(void) {
        #{type}* self = (#{type}*)#{malloc}(sizeof(#{type})); #{assert}(self);
        #{ctor}(self);
        return self;
      }
      #{elementType} #{first}(#{type}* self) {
        #{assert}(self);
        return self->head_node->element;
      }
      #{elementType} #{last}(#{type}* self) {
        #{assert}(self);
        return self->tail_node->element;
      }
      void #{append}(#{type}* self, #{elementType} element) {
        #{node}* node;
        #{assert}(self);
        node = (#{node}*)#{malloc}(sizeof(#{node})); #{assert}(node);
        node->element = element;
        node->next_node = NULL;
        if(self->tail_node) self->tail_node->next_node = node;
        self->tail_node = node;
        if(!self->head_node) self->head_node = self->tail_node;
        ++self->node_count;
      }
      void #{prepend}(#{type}* self, #{elementType} element) {
        #{node}* node;
        #{assert}(self);
        node = (#{node}*)#{malloc}(sizeof(#{node})); #{assert}(node);
        node->element = element;
        node->next_node = self->head_node;
        self->head_node = node;
        if(!self->tail_node) self->tail_node = node;
        ++self->node_count;
      }
      int #{contains}(#{type}* self, #{elementType} what) {
        #{node}* node;
        #{assert}(self);
        node = self->head_node;
        while(node) {
          if(#{comparator}(node->element, what)) {
            return 1;
          }
          node = node->next_node;
        }
        return 0;
      }
      #{elementType} #{get}(#{type}* self, #{elementType} what) {
        #{node}* node;
        #{assert}(self);
        #{assert}(#{contains}(self, what));
        node = self->head_node;
        while(node) {
          if(#{comparator}(node->element, what)) {
            return node->element;
          }
          node = node->next_node;
        }
        #{abort}();
      }
      int #{replace}(#{type}* self, #{elementType} what, #{elementType} with) {
        #{node}* node;
        #{assert}(self);
        node = self->head_node;
        while(node) {
          if(#{comparator}(node->element, what)) {
            node->element = with;
            return 1;
          }
          node = node->next_node;
        }
        return 0;
      }
      int #{replaceAll}(#{type}* self, #{elementType} what, #{elementType} with) {
        #{node}* node;
        int count = 0;
        #{assert}(self);
        node = self->head_node;
        while(node) {
          if(#{comparator}(node->element, what)) {
            node->element = with;
            ++count;
          }
          node = node->next_node;
        }
        return count;
      }
      size_t #{size}(#{type}* self) {
        #{assert}(self);
        return self->node_count;
      }
      int #{empty}(#{type}* self) {
        #{assert}(self);
        return !self->node_count;
      }
      void #{itCtor}(#{it}* self, #{type}* list) {
        #{assert}(self);
        #{assert}(list);
        self->next_node = list->head_node;
      }
      int #{itHasNext}(#{it}* self) {
        #{assert}(self);
        return self->next_node != NULL;
      }
      #{elementType} #{itNext}(#{it}* self) {
        #{node}* node;
        #{assert}(self);
        node = self->next_node;
        self->next_node = self->next_node->next_node;
        return node->element;
      }
    $
  end
end # List


class Set < Struct
  attr_reader :hasher, :comparator
  def initialize(type, element_type, hasher, comparator)
    super(type, element_type)
    @hasher = hasher
    @comparator = comparator
    @bucket = new_bucket
  end
  def new_bucket
    List.new("#{type}Bucket", elementType, comparator)
  end
  def write_intf(stream)
    @bucket.write_intf(stream)
    stream << %$
      typedef struct #{type} #{type};
      typedef struct #{it} #{it};
      struct #{type} {
        #{@bucket.type}* buckets;
        size_t bucket_count;
        size_t size;
      };
      struct #{it} {
        #{type}* set;
        int bucket_index;
        #{@bucket.it} it;
      };
      void #{ctor}(#{type}*, size_t);
      #{type}* #{new}(size_t);
      int #{contains}(#{type}*, #{elementType});
      #{elementType} #{get}(#{type}*, #{elementType});
      size_t #{size}(#{type}*);
      int #{empty}(#{type}*);
      int #{put}(#{type}*, #{elementType});
      void #{putForce}(#{type}*, #{elementType});
      void #{itCtor}(#{it}*, #{type}*);
      int #{itHasNext}(#{it}*);
      #{elementType} #{itNext}(#{it}*);
    $
  end
  def write_defs(stream)
    @bucket.write_defs(stream)
    stream << %$
      extern size_t #{hasher}(#{elementType});
      extern int #{comparator}(#{elementType}, #{elementType});
      void #{ctor}(#{type}* self, size_t bucket_count) {
        size_t i;
        #{assert}(self);
        #{assert}(bucket_count > 0);
        self->buckets = (#{@bucket.type}*)#{malloc}(bucket_count*sizeof(#{@bucket.type})); #{assert}(self->buckets);
        for(i = 0; i < bucket_count; ++i) {
          #{@bucket.ctor}(&self->buckets[i]);
        }
        self->bucket_count = bucket_count;
        self->size = 0;
      }
      #{type}* #{new}(size_t bucket_count) {
        #{type}* self = (#{type}*)#{malloc}(sizeof(#{type})); #{assert}(self);
        #{ctor}(self, bucket_count);
        return self;
      }
      int #{contains}(#{type}* self, #{elementType} element) {
        #{assert}(self);
        return #{@bucket.contains}(&self->buckets[#{hasher}(element) % self->bucket_count], element);
      }
      #{elementType} #{get}(#{type}* self, #{elementType} element) {
        #{assert}(self);
        #{assert}(#{contains}(self, element));
        return #{@bucket.get}(&self->buckets[#{hasher}(element) % self->bucket_count], element);
      }
      size_t #{size}(#{type}* self) {
        #{assert}(self);
        return self->size;
      }
      int #{empty}(#{type}* self) {
        #{assert}(self);
        return !self->size;
      }
      int #{put}(#{type}* self, #{elementType} element) {
        #{@bucket.type}* bucket;
        #{assert}(self);
        bucket = &self->buckets[#{hasher}(element) % self->bucket_count];
        if(!#{@bucket.contains}(bucket, element)) {
          #{@bucket.append}(bucket, element);
          ++self->size;
          return 1;
        } else {
          return 0;
        }
      }
      void #{putForce}(#{type}* self, #{elementType} element) {
        #{@bucket.type}* bucket;
        #{assert}(self);
        bucket = &self->buckets[#{hasher}(element) % self->bucket_count];
        if(!#{@bucket.replace}(bucket, element, element)) {
          #{@bucket.append}(bucket, element);
          ++self->size;
        }
      }
      void #{itCtor}(#{it}* self, #{type}* set) {
        #{assert}(self);
        self->set = set;
        self->bucket_index = 0;
        #{@bucket.itCtor}(&self->it, &set->buckets[0]);
      }
      int #{itHasNext}(#{it}* self) {
        #{assert}(self);
        if(#{@bucket.itHasNext}(&self->it)) {
          return 1;
        } else {
          size_t i; for(i = self->bucket_index+1; i < self->set->bucket_count; ++i) {
            if(!#{@bucket.empty}(&self->set->buckets[i])) {
              return 1;
            }
          }
          return 0;
        }
      }
      #{elementType} #{itNext}(#{it}* self) {
        #{assert}(self);
        #{assert}(#{itHasNext}(self));
          if(#{@bucket.itHasNext}(&self->it)) {
            return #{@bucket.itNext}(&self->it);
          } else {
            size_t i; for(i = self->bucket_index+1; i < self->set->bucket_count; ++i) {
            if(!#{@bucket.empty}(&self->set->buckets[i])) {
            #{@bucket.itCtor}(&self->it, &self->set->buckets[i]);
              self->bucket_index = i;
              return #{@bucket.itNext}(&self->it);
            }
          }
          #{abort}();
        }
      }
    $
  end
end # Set


class Map < Struct
  attr_reader :keyType, :hasher, :comparator
  def initialize(type, key_type, element_type, hasher, comparator)
    super(type, element_type)
    @keyType = key_type
    @hasher = hasher
    @comparator = comparator
    @pairSet = new_pair_set
  end
  def new_pair_set
    Set.new("#{type}PairSet", "#{type}Pair", "#{type}PairHasher", "#{type}PairComparator")
  end
  def write_intf(stream)
    stream << %$
      typedef struct #{pair} #{pair};
      struct #{pair} {
        #{keyType} key;
        #{elementType} element;
      };
    $
    @pairSet.write_intf(stream)
    stream << %$
      typedef struct #{type} #{type};
      typedef struct #{it} #{it};
      struct #{type} {
        #{@pairSet.type} pairs;
      };
      struct #{it} {
        #{@pairSet.it} it;
      };
      extern size_t #{hasher}(#{keyType});
      extern int #{comparator}(#{keyType}, #{keyType});
      void #{ctor}(#{type}*, size_t);
      #{type}* #{new}(size_t);
      size_t #{size}(#{type}*);
      int #{containsKey}(#{type}*, #{keyType});
      #{elementType} #{get}(#{type}*, #{keyType});
      int #{put}(#{type}*, #{keyType}, #{elementType});
      void #{putForce}(#{type}*, #{keyType}, #{elementType});
      void #{itCtor}(#{it}*, #{type}*);
      int #{itHasNext}(#{it}*);
      #{keyType} #{itNextKey}(#{it}*);
      #{elementType} #{itNextElement}(#{it}*);
      #{pair} #{itNext}(#{it}*);
    $
  end
  def write_defs(stream)
    @pairSet.write_defs(stream)
    stream << %$
      size_t #{@pairSet.hasher}(#{pair} pair) {
        return #{hasher}(pair.key);
      }
      int #{@pairSet.comparator}(#{pair} lt, #{pair} rt) {
        return #{comparator}(lt.key, rt.key);
      }
      void #{ctor}(#{type}* self, size_t bucket_count) {
        #{assert}(self);
        #{@pairSet.ctor}(&self->pairs, bucket_count);
      }
      #{type}* #{new}(size_t bucket_count) {
        #{type}* self = (#{type}*)#{malloc}(sizeof(#{type})); #{assert}(self);
        #{ctor}(self, bucket_count);
        return self;
      }
      size_t #{size}(#{type}* self) {
        return #{@pairSet.size}(&self->pairs);
      }
      int #{containsKey}(#{type}* self, #{keyType} key) {
        #{pair} pair;
        #{assert}(self);
        pair.key = key;
        return #{@pairSet.contains}(&self->pairs, pair);
      }
      #{elementType} #{get}(#{type}* self, #{keyType} key) {
        #{pair} pair;
        #{assert}(self);
        #{assert}(#{containsKey}(self, key));
        pair.key = key;
        return #{@pairSet.get}(&self->pairs, pair).element;
      }
      int #{put}(#{type}* self, #{keyType} key, #{elementType} element) {
        #{assert}(self);
        if(!#{containsKey}(self, key)) {
          #{pair} pair;
          pair.key = key; pair.element = element;
          #{@pairSet.put}(&self->pairs, pair);
          return 1;
        } else {
          return 0;
        }
      }
      void #{putForce}(#{type}* self, #{keyType} key, #{elementType} element) {
        #{pair} pair;
        #{assert}(self);
        pair.key = key; pair.element = element;
        #{@pairSet.putForce}(&self->pairs, pair);
      }
      void #{itCtor}(#{it}* self, #{type}* map) {
        #{assert}(self);
        #{assert}(map);
        #{@pairSet.itCtor}(&self->it, &map->pairs);
      }
      int #{itHasNext}(#{it}* self) {
        #{assert}(self);
        return #{@pairSet.itHasNext}(&self->it);
      }
      #{keyType} #{itNextKey}(#{it}* self) {
        #{assert}(self);
        return #{@pairSet.itNext}(&self->it).key;
      }
      #{elementType} #{itNextElement}(#{it}* self) {
        #{assert}(self);
        return #{@pairSet.itNext}(&self->it).element;
      }
      #{pair} #{itNext}(#{it}* self) {
        #{assert}(self);
        return #{@pairSet.itNext}(&self->it);
      }
    $
  end
end # Map


end # DataStruct
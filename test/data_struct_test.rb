require 'data_struct'

class M < CodeBuilder::Module

  def new_header
    H.new(self)
  end

  def new_source(index)
    S.new(self, index)
  end
end

class H < CodeBuilder::Header
  def new_stream
    File.new("data_struct_test.auto.h", 'wt')
  end
end

class S <CodeBuilder::Source
  def new_stream
    File.new("data_struct_test.auto.c", 'wt')
  end
  def write(stream)
    stream << %{#include "data_struct_test.auto.h"}
    super
  end
end

m = M.new

m << DataStruct::Array.new("DoubleArray", "double")
m << DataStruct::List.new("IntSlist", "int", "IntComparator")
m << DataStruct::Set.new("IntHset", "int", "IntHasher", "IntComparator")
m << DataStruct::Set.new("StrHset", "char*", "PcharHasher", "PcharComparator")
m << DataStruct::Map.new("StrIntHmap", "char*", "int", "PcharHasher", "PcharComparator")

m.generate
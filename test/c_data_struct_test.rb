require 'c_data_struct'

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
    File.new("c_data_struct_test.auto.h", 'wt')
  end
end

class S <CodeBuilder::Source
  def new_stream
    File.new("c_data_struct_test.auto.c", 'wt')
  end
  def write(stream)
    stream << %{#include "c_data_struct_test.auto.h"}
    super
  end
end

m = M.new

m << CDataStruct::List.new("IntSlist", "int")
m << CDataStruct::Set.new("IntHset", "int", "IntHasher", "IntComparator")
m << CDataStruct::Set.new("StrHset", "char*", "PcharHasher", "PcharComparator")
m << CDataStruct::Map.new("StrIntHmap", "char*", "int", "PcharHasher", "PcharComparator")

m.generate
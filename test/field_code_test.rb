require 'data_struct'
require 'finita/field_code'

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
    File.new("field_code_test.auto.h", 'wt')
  end
end

class S < CodeBuilder::Source
  def new_stream
    File.new("field_code_test.auto.c", 'wt')
  end
  def write(stream)
    stream << %{#include "field_code_test.auto.h"}
    super
  end
end

m = M.new
#m << Finita::RectFieldCode[Integer] << Finita::RectFieldCode[Float] << Finita::RectFieldCode[Complex]
require 'finita/evaluator_code'
m<<Finita::EvaluationMatrixCode[Float]
m.generate
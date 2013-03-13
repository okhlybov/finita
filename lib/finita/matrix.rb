require 'data_struct'
require 'finita/evaluator'


module Finita


class SparseMatrix
  attr_reader :numeric_type
  def initialize(type, numeric_type)
    @type = type
    @numeric_type = numeric_type
  end
  def code(problem_code, system_code)
    self.class::Code.new(self, problem_code, system_code, @type)
  end
  class Code < DataStruct::Code
    def entities; super + [NodeCode, NodeCoordCode, NodeSetCode, @matrix_code, @fp_code] end
    def initialize(matrix, problem_code, system_code, type)
      @matrix = matrix
      @matrix_code = MatrixCode[@matrix.numeric_type]
      @fp_code = FunctionPtrCode[@matrix.numeric_type]
      @c_type = CType[@matrix.numeric_type]
      super(type)
    end
    def write_intf(stream)
      stream << %$
        int #{ctor}(size_t);
        void #{merge}(#{NodeCode.type}, #{NodeCode.type}, #{@fp_code.type});
        #{@c_type} #{value}(#{NodeCode.type}, #{NodeCode.type});
      $
    end
    def write_defs(stream)
      stream << %$
        static #{@matrix_code.type} #{matrix};
        static #{NodeSetCode.type} #{rows}, #{columns};
        int #{ctor}(size_t entry_count) {
          #{@matrix_code.ctor}(&#{matrix}, entry_count);
          #{NodeSetCode.ctor}(&#{rows}, entry_count);
          #{NodeSetCode.ctor}(&#{columns}, entry_count);
        }
        void #{merge}(#{NodeCode.type} row, #{NodeCode.type} column, #{@fp_code.type} fp) {
          #{@matrix_code.merge}(&#{matrix}, row, column, fp);
          #{NodeSetCode.put}(&#{rows}, row);
          #{NodeSetCode.put}(&#{columns}, column);
        }
        #{@c_type} #{value}(#{NodeCode.type} row, #{NodeCode.type} column) {
          return #{@matrix_code.evaluate}(&#{matrix}, row, column);
        }
      $
    end
  end # Code
end # SparseMatrix


end # Finita
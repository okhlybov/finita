require 'finita/common'
require 'finita/generator'


module Finita::Backend


class BackendCode < Finita::CodeTemplate

  attr_reader :system, :name, :scalar_type, :func_matrix_code, :func_vector_code

  def entities; super + [Finita::Mapper::StaticCode.instance] end

  def initialize(backend, gtor, system)
    @gtor = gtor
    @backend = backend
    @system = system
    @name = system.name
    @scalar_type = Finita::Generator::Scalar[system.type]
    @func_matrix_code = Finita::FuncMatrix::Code[system.type]
    @func_vector_code = Finita::FuncVector::Code[system.type]
    gtor << self
  end

  def write_intf(stream)
    stream << %$
      typedef struct {
        int row, column;
        #{scalar_type} value;
      } #{name}NumericMatrix;
      typedef struct {
        int row;
        #{scalar_type} value;
      } #{name}NumericVector;
      extern int #{name}NNZ, #{name}NEQ;
      extern #{name}NumericMatrix* #{name}LHS;
      extern #{name}NumericVector* #{name}RHS;
      void #{name}SetupBackend();
      void #{name}SolveLinearSystem();
    $
  end

  def write_defs(stream)
    stream << %$
      extern FinitaMapper #{name}Mapper;
      extern #{func_matrix_code.type} #{name}SymbolicMatrix;
      extern #{func_vector_code.type} #{name}SymbolicVector;
      int #{name}NNZ, #{name}NEQ;
      #{name}NumericMatrix* #{name}LHS;
      #{name}NumericVector* #{name}RHS;
      static void #{name}SetupBackendStruct() {
        int i;
        #{func_matrix_code.it} it;
        FINITA_ASSERT(FinitaMapperSize(&#{name}Mapper) == #{func_vector_code.size}(&#{name}SymbolicVector));
        #{name}NNZ = #{func_matrix_code.size}(&#{name}SymbolicMatrix);
        #{name}NEQ = FinitaMapperSize(&#{name}Mapper);
        #{name}LHS = (#{name}NumericMatrix*)FINITA_MALLOC(sizeof(#{name}NumericMatrix)*#{name}NNZ); FINITA_ASSERT(#{name}LHS);
        #{func_matrix_code.it_ctor}(&it, &#{name}SymbolicMatrix);
        i = 0;
        while(#{func_matrix_code.it_has_next}(&it)) {
          #{func_matrix_code.pair} pair = #{func_matrix_code.it_next}(&it);
          #{name}LHS[i].row = FinitaMapperIndex(&#{name}Mapper, pair.key.row);
          #{name}LHS[i].column = FinitaMapperIndex(&#{name}Mapper, pair.key.column);
          ++i;
        }
        FINITA_ASSERT(i == #{func_matrix_code.size}(&#{name}SymbolicMatrix));
        #{name}RHS = (#{name}NumericVector*)FINITA_MALLOC(sizeof(#{name}NumericVector)*#{name}NEQ); FINITA_ASSERT(#{name}RHS);
        for(i = 0; i < #{name}NEQ; ++i) {
          #{name}RHS[i].row = i;
        }
      }
    $
  end

end # BackendCode


class SuperLU

  class Code < BackendCode

    def write_intf(stream)
      super
      stream << %$\n#include "slu_ddefs.h"\n$ if system.type == Float
      stream << %$\n#include "slu_cdefs.h"\n$ if system.type == Complex
    end

    def write_defs(stream)
      super
      tag = :d if system.type == Float
      tag = :c if system.type == Complex
      stream << %$
        static int* #{name}XA;
        static int* #{name}ASub;
        static int* #{name}PermC;
        static int* #{name}PermR;
        static int #{name}ColumnFirstSort(const void* l, const void* r) {
          #{name}NumericMatrix* lt = (#{name}NumericMatrix*)l;
          #{name}NumericMatrix* rt = (#{name}NumericMatrix*)r;
          if(lt->column < rt->column)
            return -1;
          else if(lt->column > rt->column)
            return +1;
          else if(lt->row < rt->row)
            return -1;
          else if(lt->row > rt->row)
            return +1;
          else
            return 0;
        }
        void #{name}SetupBackend() {
          int i, j, c;
          #{name}SetupBackendStruct();
          #{name}ASub = (int*)FINITA_MALLOC(sizeof(int)*#{name}NNZ); FINITA_ASSERT(#{name}ASub);
          #{name}XA = (int*)FINITA_MALLOC(sizeof(int)*(#{name}NEQ+1)); FINITA_ASSERT(#{name}XA);
          #{name}PermC = (int*)FINITA_MALLOC(sizeof(int)*#{name}NEQ); FINITA_ASSERT(#{name}PermC);
          #{name}PermR = (int*)FINITA_MALLOC(sizeof(int)*#{name}NEQ); FINITA_ASSERT(#{name}PermR);
          qsort(#{name}LHS, #{name}NNZ, sizeof(#{name}NumericMatrix), #{name}ColumnFirstSort);
          for(i = j = 0, c = -1; i < #{name}NNZ; ++i) {
            #{name}ASub[i] = #{name}LHS[i].row;
            if(c < #{name}LHS[i].column) {
              c = #{name}LHS[i].column;
              #{name}XA[j++] = i;
            }
          }
          #{name}XA[j] = i;
        }
        void #{name}SolveLinearSystem() {
          int i;
          int* ASub;
          int* XA;
          #{scalar_type}* LHS;
          #{scalar_type}* RHS;
          SuperMatrix A, B, L, U;
          superlu_options_t Opts;
          SuperLUStat_t Stat;
          int Info;
          ASub = (int*)FINITA_MALLOC(sizeof(int)*#{name}NNZ); FINITA_ASSERT(ASub);
          XA = (int*)FINITA_MALLOC(sizeof(int)*(#{name}NEQ+1)); FINITA_ASSERT(XA);
          LHS = (#{scalar_type}*)FINITA_MALLOC(sizeof(#{scalar_type})*#{name}NNZ); FINITA_ASSERT(LHS);
          RHS = (#{scalar_type}*)FINITA_MALLOC(sizeof(#{scalar_type})*#{name}NEQ); FINITA_ASSERT(RHS);
          memcpy(ASub, #{name}ASub, sizeof(int)*#{name}NNZ);
          memcpy(XA, #{name}XA, sizeof(int)*(#{name}NEQ+1));
          for(i = 0; i < #{name}NNZ; ++i) {
            LHS[i] = #{name}LHS[i].value;
          }
          for(i = 0; i < #{name}NEQ; ++i) {
            RHS[i] = #{name}RHS[i].value;
          }
          set_default_options(&Opts);
          StatInit(&Stat);
          #{tag}Create_CompCol_Matrix(&A, #{name}NEQ, #{name}NEQ, #{name}NNZ, LHS, ASub, XA, SLU_NC, SLU_D, SLU_GE);
          #{tag}Create_Dense_Matrix(&B, #{name}NEQ, 1, RHS, #{name}NEQ, SLU_DN, SLU_D, SLU_GE);
          #{tag}gssv(&Opts, &A, #{name}PermC, #{name}PermR, &L, &U, &B, &Stat, &Info);
          for(i = 0; i < #{name}NEQ; ++i) {
            #{name}RHS[i].value =  RHS[i];
          }
          Destroy_CompCol_Matrix(&A); /* implicitly frees LHS, ASub, XA */
          Destroy_Dense_Matrix(&B); /* implicitly frees RHS */
          Destroy_SuperNode_Matrix(&L);
          Destroy_CompCol_Matrix(&U);
          StatFree(&Stat);
        }
      $
    end

  end # Code

  def bind(gtor, system)
    Code.new(self, gtor, system)
  end

end # SuperLU


end # Finita::Backend
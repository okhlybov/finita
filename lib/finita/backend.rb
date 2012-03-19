require 'finita/common'
require 'finita/generator'


module Finita::Backend


class BackendCode < Finita::CodeTemplate

  attr_reader :system, :name, :type

  def entities; super + [Finita::Orderer::StaticCode.instance] end

  def initialize(backend, gtor, system)
    @gtor = gtor
    @backend = backend
    @system = system
    @name = system.name
    @type = Finita::Generator::Scalar[system.type]
    gtor << self
  end

  def write_intf(stream)
    stream << %$
      typedef struct {
        int row, column;
        #{type} value;
      } #{name}Matrix;
      typedef struct {
        int row;
        #{type} value;
      } #{name}Vector;
      extern FinitaOrderer #{name}Orderer;
      extern size_t #{name}NNZ, #{name}NEQ;
      extern #{name}Matrix* #{name}LHS;
      extern #{name}Vector* #{name}RHS;
      void #{name}SetupBackend();
      void #{name}SolveLinearSystem();
    $
  end

  def write_defs(stream)
    stream << %$
      size_t #{name}NNZ, #{name}NEQ;
      #{name}Matrix* #{name}LHS;
      #{name}Vector* #{name}RHS;
      static void #{name}SetupBackendStruct() {
        int i;
        FinitaRowColumn* rc;
        #{name}EvaluatorRowColumn(&rc, &#{name}NNZ);
        #{name}LHS = (#{name}Matrix*)FINITA_MALLOC(sizeof(#{name}Matrix)*#{name}NNZ); FINITA_ASSERT(#{name}LHS);
        for(i = 0; i < #{name}NNZ; ++i) {
          #{name}LHS[i].row = rc[i].row;
          #{name}LHS[i].column = rc[i].column;
        }
        FINITA_FREE(rc);
        #{name}NEQ = FinitaOrdererSize(&#{name}Orderer);
        #{name}RHS = (#{name}Vector*)FINITA_MALLOC(sizeof(#{name}Vector)*#{name}NEQ); FINITA_ASSERT(#{name}RHS);
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
          #{name}Matrix* lt = (#{name}Matrix*)l;
          #{name}Matrix* rt = (#{name}Matrix*)r;
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
          qsort(#{name}LHS, #{name}NNZ, sizeof(#{name}Matrix), #{name}ColumnFirstSort);
          #{name}ASub = (int*)FINITA_MALLOC(sizeof(int)*#{name}NNZ); FINITA_ASSERT(#{name}ASub);
          #{name}XA = (int*)FINITA_MALLOC(sizeof(int)*(#{name}NEQ+1)); FINITA_ASSERT(#{name}XA);
          #{name}PermC = (int*)FINITA_MALLOC(sizeof(int)*#{name}NEQ); FINITA_ASSERT(#{name}PermC);
          #{name}PermR = (int*)FINITA_MALLOC(sizeof(int)*#{name}NEQ); FINITA_ASSERT(#{name}PermR);
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
          #{type}* LHS;
          #{type}* RHS;
          SuperMatrix A, B, L, U;
          superlu_options_t Opts;
          SuperLUStat_t Stat;
          int Info;
          ASub = (int*)FINITA_MALLOC(sizeof(int)*#{name}NNZ); FINITA_ASSERT(ASub);
          XA = (int*)FINITA_MALLOC(sizeof(int)*(#{name}NEQ+1)); FINITA_ASSERT(XA);
          LHS = (#{type}*)FINITA_MALLOC(sizeof(#{type})*#{name}NNZ); FINITA_ASSERT(LHS);
          RHS = (#{type}*)FINITA_MALLOC(sizeof(#{type})*#{name}NEQ); FINITA_ASSERT(RHS);
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
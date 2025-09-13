
import ../../Python/versionInfo
import ../../Utils/intflags

declareIntFlag PyCodeFutureOption:
  DIVISION         = 0x020000 ## CO_FUTURE_DIVISION
  ABSOLUTE_IMPORT  = 0x040000 ## CO_FUTURE_ABSOLUTE_IMPORT
  WITH_STATEMENT   = 0x080000 ## CO_FUTURE_WITH_STATEMENT
  PRINT_FUNCTION   = 0x100000 ## CO_FUTURE_PRINT_FUNCTION
  UNICODE_LITERALS = 0x200000 ## CO_FUTURE_UNICODE_LITERALS
  BARRY_AS_BDFL    = 0x400000 ## CO_FUTURE_BARRY_AS_BDFL
  GENERATOR_STOP   = 0x800000 ## CO_FUTURE_GENERATOR_STOP
  ANNOTATIONS      = 0x1000000 ## CO_FUTURE_ANNOTATIONS

const PyCF_ONLY_AST = 0x0400
declareIntFlag PyCF:
  SOURCE_IS_UTF8        = 0x0100
  DONT_IMPLY_DEDENT     = 0x0200
  ONLY_AST              = PyCF_ONLY_AST
  IGNORE_COOKIE         = 0x0800
  TYPE_COMMENTS         = 0x1000
  ALLOW_TOP_LEVEL_AWAIT = 0x2000
  ALLOW_INCOMPLETE_INPUT= 0x4000
  OPTIMIZED_AST         = (0x8000 or PyCF_ONLY_AST)

type
  PyCFlag = IntFlag[PyCodeFutureOption|Py_CF]
  PyCompilerFlagsObj = object
    ## CPython's PyCompilerFlags
    flags*: PyCFlag ## bitmask of CO_xxx flags relevant to future
    feature_version*: int  ## minor Python version (PyCF_ONLY_AST)
  PyCompilerFlags* = ref PyCompilerFlagsObj
#[bpo-39562: CO_FUTURE_ and PyCF_ constants must be kept unique.
   PyCF_ constants can use bits from 0x0100 to 0x10000.
   CO_FUTURE_ constants use bits starting at 0x20000]#

template genMixOp(typ){.dirty.} =  
  proc `&`*(a: PyCFlag, b: typ): bool = (cint(a) and cint(b)) != 0
  proc `|`*(a: PyCFlag, b: typ): PyCFlag = PyCFlag(cint(a) or cint(b))

genMixOp PyCodeFutureOption
genMixOp PyCF

template initPyCompilerFlags*(f = PyCFlag(0); fv = PyMinor): PyCompilerFlags =
  PyCompilerFlags(flags: f, feature_version: fv)

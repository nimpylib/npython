
import ./intflags
export intflags
declareIntFlag NPyExportcFlags:
  convAuto = 0  ## automatic conversion, e.g. string to cstring. default
  noStringConv  ## Not use cstring for string parameters
  boolRetAsCInt  ## convert bool return value to cint

type
  NPyExportcFlagsSet* = IntFlag[NPyExportcFlags]


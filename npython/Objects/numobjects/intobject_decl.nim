
import ./intobject/[decl, frexp, signbit]
export decl, frexp, signbit
import pkg/intobject/ops_tofloat

import ../[
  pyobjectBase, exceptions,
  stringobject,
]

proc toFloat*(pyInt: PyIntObject; overflow: var PyOverflowErrorObject): float{.pyCFuncPragma.} =
  ## `PyLong_AsDouble`
  overflow = if pyInt.v.toFloat(result): nil
  else: newOverflowError newPyAscii"int too large to convert to float"

proc toFloat*(pyInt: PyIntObject; overflow: var bool): float{.pyCFuncPragma.} =
  pyInt.v.toFloat(overflow)

proc toFloat*(pyInt: PyIntObject): float{.pyCFuncPragma.} =
  ## `PyLong_AsDouble` but never OverflowError, just returns `+-Inf`
  pyInt.v.toFloat

proc toFloat*(pyInt: PyIntObject; res: var float): PyOverflowErrorObject{.pyCFuncPragma.} =
  res = pyInt.toFloat result

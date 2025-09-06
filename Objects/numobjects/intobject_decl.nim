
import ./intobject/[decl, frexp, signbit]
export decl, frexp, signbit

import ../[
  pyobjectBase, exceptions,
]
import ../../Utils/utils
const HasLdExp = declared(ldexp)
when not HasLdExp:
  import std/strutils

proc toFloat*(pyInt: PyIntObject; overflow: var PyOverflowErrorObject): float{.pyCFuncPragma.} =
  ## `PyLong_AsDouble`
  overflow = nil
  when not HasLdexp:
    ValueError!parseFloat($pyInt)  #TODO:long-opt
  else:
    var exponent: int64
    let x = frexp(pyInt, exponent)
    assert exponent >= 0
    if exponent > DBL_MAX_EXP:
      overflow = newOverflowError newPyAscii"int too large to convert to float"
      return -1.0
    ldexp(x, cint exponent)


proc toFloat*(pyInt: PyIntObject): float{.pyCFuncPragma.} =
  ## `PyLong_AsDouble` but never OverflowError, just returns `+-Inf`
  var ovf: PyOverflowErrorObject
  result = pyInt.toFloat ovf
  if ovf.isNil: return
  result = if pyInt.negative: NegInf
  else: Inf

proc toFloat*(pyInt: PyIntObject; res: var float): PyOverflowErrorObject{.pyCFuncPragma.} =
  res = pyInt.toFloat result

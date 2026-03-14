
from std/math import isNaN, classify, FloatClass, pow, `mod`, copySign, floor
import ./decl
import ../../[
  pyobjectBase,
  exceptions, stringobject,
]
import ../complexobject/[decl, pow]

proc isOddInteger(f: float): bool =
  ## DOUBLE_IS_ODD_INTEGER
  f mod 2 == 1

when defined(c) or defined(cpp) or defined(objc):
  proc isinf(f: float): bool{.importc, header: "<math.h>", cdecl.}
else:
  proc isinf(f: float): bool =
    f == Inf or f == NegInf

proc pow*(self: PyFloatObject, iw: float): PyObject =
  template retf(f) =
    return newPyFloat f
  var
    iv = self.v
  if iw == 0:
    retf 1.0
  if iv.isNaN:
    retf iv
  if iw.isNaN:
    retf if iv == 1.0: 1.0
    else: iw
  if iw.isInf:
    iv = abs iv
    if iv == 1:
      retf 1.0
    elif (iw > 0) == (iv > 1):
      retf abs iw
    else:
      retf 0.0
  if iv.isInf:
    let iw_is_odd = isOddInteger(iw)
    retf if iw > 0:
      if iw_is_odd: iv
      else: abs iv
    else:
      if iw_is_odd: copySign(0.0, iv)
      else: 0.0

  if iv == 0.0:
    let iw_is_odd = iw mod 2 == 1
    if iw < 0:
      return newZeroDivisionError newPyAscii"zero to a negative power"
    retf if iw_is_odd: iv
    else: 0.0
  var negative_result = false
  if iv < 0:
    if iw != floor(iw):
      return complex_pow(newPyComplex(self.v), newPyFloat(iw))
    iv = -iv
    negative_result = isOddInteger(iw)
  if iv == 1:
    retf if negative_result: -1.0
    else: 1.0
  var res = pow(iv, iw)
  if negative_result:
    res = -res
  if res.isInf:
    return newOverflowError newPyAscii"math result not representable"
  retf res

proc pow*(self, other: PyFloatObject): PyObject{.inline.} = self.pow(other.v)

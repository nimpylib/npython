import std/[tables, macros, strutils, math]

import ../numobjects_comm
export intobject_decl except Digit, TwoDigits, SDigit, digitBits, truncate,
 IntSign
import ./[
  bit_length, signbit,
  ops_basic_arith, ops_toint
]
import pkg/intobject/ops

import ./private/dispatch

export bit_length, signbit, ops_basic_arith, ops_toint
import ../../stringobject/strformat
import ../floatobject/pow
import ../../../Include/internal/pycore_int
export PY_INT_MAX_STR_DIGITS_THRESHOLD, PY_INT_DEFAULT_MAX_STR_DIGITS

export pyIntZero, pyIntOne, pyIntTen

using self: PyIntObject

proc `mod`*(a: PyIntObject, n: TwoDigits|SomeUnsignedIntSmallerThanTwoDigits): PyIntObject =
  ## Get the remainder of an integer divided by a fixed-width integer.
  ## The sign of `a` is ignored; `n` should not be zero.
  ## 
  ## .. hint::
  ##   Other mixin ops against fixed-width integer are implemented in
  ##   `ops_mix_nim.nim`<./ops_mix_nim.html>_
  newPyInt a.v mod n

template chkRaiseDivByZero(res) =
  try: result = res
  except DivByZeroDefect:
    retZeroDiv

# `long_div`
template genDivOrMod(floorOp, pyFloorOp, pyOp){.dirty.} =
  proc `floorOp NonZero`*(a, b: PyIntObject): PyIntObject =
    ## Integer division
    ## 
    ## assuming b is non-zero
    newPyInt `floorOp NonZero`(a.v, b.v)

  dispatchBin `floorOp`

  proc pyFloorOp*(a, b: PyIntObject): PyObject{.pyCFuncPragma.} =
    ## .. note:: this returns ZeroDivisionError when b is zero
    chkRaiseDivByZero newPyInt pyFloorOp(a.v, b.v)
  
  proc pyOp*(a, b: PyIntObject): PyIntObject =
    ## .. note:: this raises DivByZeroDefect when b is zero
    newPyInt pyOp(a.v, b.v)

genDivOrMod floordiv, `//`, `div`
genDivOrMod floormod, `%` , `mod`

template retTupBody(op, a, b): untyped{.dirty.} =
  let t = op(a.v, b.v)
  (t[0].newPyInt, t[1].newPyInt)

proc divmodNonZero*(a, b: PyIntObject): tuple[d, m: PyIntObject] =
  ## export for builtins.divmod
  retTupBody(divmodNonZero, a, b)

proc divmod*(a, b: PyIntObject): tuple[d, m: PyIntObject] =
  ## .. note::
  ##   this is Python's `divmod`(get division and modulo),
  ##   ref `divrem`_ for Nim's std/math divmod
  ##
  ## .. hint:: this raises DivByZeroDefect when b is zero
  retTupBody(divmod, a, b)

proc divrem*(a, b: PyIntObject): tuple[d, r: PyIntObject] =
  ## .. hint:: this raises DivByZeroDefect when b is zero
  retTupBody(divmodNonZero, a, b)

# a**b
dispatchBin powPos
proc powNeg*(a, b: PyIntObject): PyObject =
  assert b.negative
  return newPyFloat(a.toFloat).pow b.toFloat

proc pow*(a, b: PyIntObject): PyObject =
  ## returns:
  ##
  ##   - int if `b` >= 0
  ##   - float if `b` < 0
  case b.sign
  of Negative: powNeg(a, b)
  of Positive: powPos(a, b)
  of Zero: pyIntOne

proc parseInt*[C: char|Rune](s: openArray[C]; res: var PyIntObject): int =
  ## with `base = 0` (a.k.a. support prefix like 0b)
  ## and ignore `sys.flags.int_max_str_digits`
  var r: IntObject
  result = parseInt(s, r)
  res = newPyInt r

proc newPyIntFromStr*[C: char|Rune](s: openArray[C]): PyIntObject{.raises: [ValueError].} =
  ## This ignores `sys.flags.int_max_str_digits`
  newPyInt parseIntObject(s)

template invBaseRet =
  return newValueError newPyAscii"int() arg 2 must be >= 2 and <= 36"

proc retInvIntCallImpl(strObj: PyObject, base: SomeInteger): PyObject{.inline.} =
  newPyStr&"invalid literal for int() with base {base}: {strObj:.200R}"

template retInvIntCall*(strObj: PyObject, base: SomeInteger){.dirty.} =
  ## inner
  bind retInvIntCallImpl
  let s = retInvIntCallImpl(strObj, base)
  retIfExc s
  return newValueError PyStrObject s

template get_max_str_digits*(): int =
  PyInterpreterState_GET_long_state().max_str_digits

proc fromStr*[C: char](res: var PyIntObject; s: openArray[C]; nParsed: var int; base: int = 10): PyBaseErrorObject =
  res = newPyIntSimple()
  case res.v.fromStr(s, nParsed, base)
  of Ok: return
  of InvalidBase: invBaseRet
  of InvalidLiteral:
    let strObj = newPyStr(s)
    retIfExc PyObject strObj
    retInvIntCall strObj, base
  of ExceedsMaxStrDigits:
    return newValueError newPyAscii MAX_STR_DIGITS_errMsg_to_int(get_max_str_digits(), s.len)

proc PyLong_FromString*[C: char](s: openArray[C]; nParsed: var int; base: int = 10): PyObject =
  var res: PyIntObject
  result = res.fromStr(s, nParsed, base)
  if result.isNil: result = res

template chkFormatOvf(res: bool) =
  if not res:
    return newOverflowError newPyAscii"int too large to convert"

proc format_binary*(a: PyIntObject, base: uint8, alternate: bool, v: var string): PyBaseErrorObject =
  ## long_format_binary
  chkFormatOvf a.v.format_binary(base, alternate, v)

method `$`*(i: PyIntObject): string{.raises: [].} =
  ## this ignores `sys.flags.int_max_str_digits`,
  ##  and may raises `OverflowDefect` if `i` contains too many digits
  $i.v

proc toStringCheckThreshold*(a: PyIntObject, v: var string): PyBaseErrorObject{.raises: [].} =
  ## this respects `sys.flags.int_max_str_digits`
  if not a.v.toStringCheckThreshold(v):
    return newOverflowError newPyAscii MAX_STR_DIGITS_errMsg_to_str(get_max_str_digits())

proc format*(i: PyIntObject, base: uint8, s: var string): PyBaseErrorObject =
  # `_PyLong_Format`
  # `s` is a `out` param
  chkFormatOvf format(i.v, base, s)

proc newPyInt*[C: char](smallInt: C): PyIntObject =
  newPyInt int smallInt  # TODO

proc newPyInt*[C: Rune|char](str: openArray[C]): PyIntObject = 
  newPyIntFromStr(str)

proc newPyInt*(dval: float): PyObject =
  ## `PyLong_FromDouble`
  case dval.classify
  of fcInf, fcNegInf:
    return newOverflowError(newPyAscii"cannot convert float infinity to integer")
  of fcNan:
    return newValueError(newPyAscii"cannot convert float NaN to integer")
  else: discard
  newPyInt newIntFromNormalFloat(dval)

when isMainModule:
  #let a = fromStr("-1234567623984672384623984712834618623")
  #let a = fromStr("3234567890")
  #[
  echo a
  echo a + a
  echo a + a - a
  echo a + a - a - a
  echo a + a - a - a - a
  ]#
  #let a = fromStr("88888888888888")
  let a = newPyInt("100000000000")
  echo a.pow(pyIntTen)
  echo a
  #echo a * pyIntTen
  #echo a.pow pyIntTen
  #let a = fromStr("100000000000")
  #echo a
  #echo a * fromStr("7") - a - a - a - a - a - a - a
  #let b = newPyInt(2)
  #echo pyIntTen
  #echo -pyIntTen
  #echo a
  #echo int(a)
  #echo -int(a)
  #echo IntSign(-int(a))
  #echo newPyInt(3).pow(pyIntTwo) - pyIntOne + pyIntTwo
  #echo a div b
  #echo a div b * newPyInt(2)

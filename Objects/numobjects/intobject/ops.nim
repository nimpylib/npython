import tables
import algorithm
import macros
import strutils
import math

import ../numobjects_comm
export intobject_decl except Digit, TwoDigits, SDigit, digitBits, truncate,
 IntSign
import ./[
  bit_length, bit_length_util, shift, signbit,
  fromStrUtils, utils,
  ops_basic_private, ops_basic_arith, ops_toint
]
export bit_length, signbit, ops_basic_arith, ops_toint
import ../../stringobject/strformat
import ../../../Modules/unicodedata/[decimal, space]
from ../../../Utils/utils import unreachable
import ../../../Include/internal/pycore_int
export PY_INT_MAX_STR_DIGITS_THRESHOLD, PY_INT_DEFAULT_MAX_STR_DIGITS

type STwoDigit = SDigit

const maxValue = TwoDigits(high(Digit)) + 1

export pyIntZero, pyIntOne, pyIntTen
let pyIntTwo = newPyInt(2)

using self: PyIntObject
template fastExtract(a, b){.dirty.} =
  let
    left = SDigit a.digits[0]
    right = SDigit b.digits[0]
  when check:
    assert a.digits.len == 1
    assert b.digits.len == 1

proc fast_floor_div(a, b: PyIntObject; check: static[bool] = true): PyIntObject =
  fastExtract a, b
  newPyInt floorDiv(left, right)

proc fast_mod(a, b: PyIntObject; check: static[bool] = true): PyIntObject =
  fastExtract a, b
  #let sign = b.compatSign
  newPyInt floorMod(left, right)  

proc inplaceDivRem1(pout: var openArray[Digit], pin: openArray[Digit], size: int, n: Digit): Digit =
  ## Perform in-place division with remainder for a single digit
  var remainder: TwoDigits = 0
  assert n > 0 and n < maxValue

  for i in countdown(size - 1, 0):
    let dividend = (remainder shl digitBits) or TwoDigits(pin[i])
    let quotient = truncate(dividend div n)
    remainder = dividend mod n
    pout[i] = quotient

  return Digit(remainder)

proc divRem1(a: PyIntObject, n: Digit, remainder: var Digit): PyIntObject =
  ## Divide an integer by a single digit, returning both quotient and remainder
  ## The sign of a is ignored; n should not be zero.
  ## 
  ## the result's sign is always positive
  assert n > 0 and n < maxValue
  let size = a.digits.len
  let quotient = newPyIntOfLen(size)
  remainder = inplaceDivRem1(quotient.digits, a.digits, size, n)
  quotient.normalize()
  return quotient

proc inplaceRem1(pin: var seq[Digit], size: int, n: Digit): Digit =
  ## Compute the remainder of a multi-digit integer divided by a single digit.
  ## `pin` points to the least significant digit (LSD).
  var rem: TwoDigits = 0
  assert n > 0 and n <= maxValue - 1

  for i in countdown(size - 1, 0):
    rem = ((rem shl digitBits) or TwoDigits(pin[i])) mod TwoDigits(n)

  return Digit(rem)

proc rem1(a: PyIntObject, n: Digit): PyIntObject =
  ## Get the remainder of an integer divided by a single digit.
  ## The sign of `a` is ignored; `n` should not be zero.
  assert n > 0 and n <= maxValue - 1
  let size = a.digits.len
  let remainder = inplaceRem1(a.digits, size, n)
  return newPyInt(remainder)

proc tryRem(a, b: PyIntObject, prem: var PyIntObject): bool{.pyCFuncPragma.}
proc lMod(v, w: PyIntObject, modRes: var PyIntObject): bool{.pyCFuncPragma.} =
  ## Compute modulus: *modRes = v % w
  ## returns w != 0
  #assert modRes != nil
  if v.digits.len == 1 and w.digits.len == 1:
    modRes = fast_mod(v, w)
    return not modRes.isNil

  if not tryRem(v, w, modRes):
    return

  # Adjust signs if necessary
  if (modRes.sign == Negative and w.sign == Positive) or
     (modRes.sign == Positive and w.sign == Negative):
    modRes = modRes + w


proc `%`*(a, b: PyIntObject): PyObject{.pyCFuncPragma.} =
  var res: PyIntObject
  if lMod(a, b, res):
    retZeroDiv
  result = res

proc lDivmod(v, w: PyIntObject, divRes, modRes: var PyIntObject): bool {.pyCFuncPragma.}

template fastDivIf1len(a, b: PyIntObject) =
  if a.digits.len == 1 and b.digits.len == 1:
    return fast_floor_div(a, b)

template lDiv(a, b: PyIntObject; result): bool =
  var unused: PyIntObject
  lDivmod(a, b, result, unused)

proc floorDivNonZero*(a, b: PyIntObject): PyIntObject =
  ## `long_div`
  ## Integer division
  ## 
  ## assuming b is non-zero
  fastDivIf1len a, b
  assert lDiv(a, b, result)

proc `//`*(a, b: PyIntObject): PyObject{.pyCFuncPragma.} =
  ## `long_div`
  ## Integer division
  ## 
  ## .. note:: this may returns ZeroDivisionError
  fastDivIf1len a, b
  var res: PyIntObject
  if lDiv(a, b, res):
    return res
  retZeroDiv

proc divmodNonZero*(a, b: PyIntObject): tuple[d, m: PyIntObject] =
  ## export for builtins.divmod
  assert lDivmod(a, b, result.d, result.m)

proc divmod*(a, b: PyIntObject): tuple[d, m: PyIntObject] =
  if not lDivmod(a, b, result.d, result.m):
    raise newException(ValueError, "division by zero")

proc xDivRem(v1, w1: PyIntObject, prem: var PyIntObject): PyIntObject =
  ## `x_divrem`
  ## Perform unsigned integer division with remainder
  var v, w, a: PyIntObject
  var sizeV = v1.digits.len
  var sizeW = w1.digits.len
  assert sizeV >= sizeW and sizeW >= 2

  # Allocate space for v and w
  v = newPyIntSimple()
  v.digits.setLen(sizeV + 1)
  w = newPyIntSimple()
  w.digits.setLen(sizeW)

  # Normalize: shift w1 left so its top digit is >= maxValue / 2
  let d = digitBits - bitLength(w1.digits[^1])
  let carryW = vLShift(w.digits, w1.digits, sizeW, d)
  assert carryW == 0
  let carryV = vLShift(v.digits, v1.digits, sizeV, d)
  if carryV != 0 or v.digits[^1] >= w.digits[^1]:
    v.digits.add carryV
    inc sizeV

  # Quotient has at most `k = sizeV - sizeW` digits
  let k = sizeV - sizeW
  assert k >= 0
  a = newPyIntSimple()
  a.digits.setLen(k)

  var v0 = v.digits
  let w0 = w.digits
  let wm1 = w0[^1]
  let wm2 = w0[^2]

  for vk in countdown(k - 1, 0):
    # Estimate quotient digit `q`
    let vtop = v0[vk + sizeW]
    assert vtop <= wm1
    let vv = (TwoDigits(vtop) shl digitBits) or TwoDigits(v0[vk + sizeW - 1])
    var q = Digit(vv div wm1)
    var r = Digit(vv mod wm1)

    while TwoDigits(wm2) * TwoDigits(q) > ((TwoDigits(r) shl digitBits) or TwoDigits(v0[vk + sizeW - 2])):
      dec q
      r += wm1
      if r >= maxValue:
        break
    assert q <= maxValue

    # Subtract `q * w0[0:sizeW]` from `v0[vk:vk+sizeW+1]`
    var zhi: SDigit = 0
    for i in 0..<sizeW:
      let z = (SDigit(v0[vk + i]) + zhi).STwoDigit - STwoDigit(q) * STwoDigit(w0[i])
      v0[vk + i] = truncate(cast[Digit](z))
      zhi = z shr digitBits

    let svtop = SDigit vtop
    assert svtop + zhi == -1 or svtop + zhi == 0
    # Add back `w` if `q` was too large
    if svtop + zhi < 0:
      var carry = Digit 0
      for i in 0..<sizeW:
        carry += v0[vk + i] + w0[i]
        v0[vk + i] = truncate(carry)
        carry = carry shr digitBits
      dec q

    # Store quotient digit
    a.digits[vk] = q

  # Unshift remainder
  let carry = vRShift(w.digits, v0, sizeW, d)
  assert carry == 0
  prem = w
  return a

proc tryRem(a, b: PyIntObject, prem: var PyIntObject): bool{.pyCFuncPragma.} =
  ## `long_rem`
  ## Integer reminder.
  ## 
  ## returns if `b` is non-zero  (only false when b is zero)
  let sizeA = a.digits.len
  let sizeB = b.digits.len

  if sizeB == 0:
    #raise newException(ZeroDivisionError, "division by zero")
    return

  result = true
  if sizeA < sizeB or (
      sizeA == sizeB and a.digits[^1] < b.digits[^1]):
      # |a| < |b|
    prem = newPyInt(a)
    return

  if sizeB == 1:
    prem = rem1(a, b.digits[0])
  else:
    discard xDivRem(a, b, prem)

  #[ Set the sign.]#
  if (a.sign == Negative) and not prem.zero():
    prem.setSignNegative()

proc tryDivrem(a, b: PyIntObject, pdiv, prem: var PyIntObject): bool =
  ## `long_divrem`
  ## Integer division with remainder
  ## 
  ## returns if `b` is non-zero  (only false when b is zero)
  let sizeA = a.digits.len
  let sizeB = b.digits.len

  if sizeB == 0:
    #raise newException(ZeroDivisionError, "division by zero")
    return

  result = true
  if sizeA < sizeB or (
      sizeA == sizeB and a.digits[^1] < b.digits[^1]):
      # |a| < |b|
    prem = newPyInt(a)
    pdiv = pyIntZero
    return

  if sizeB == 1:
    var remainder: Digit
    pdiv = divRem1(a, b.digits[0], remainder)
    prem = newPyInt(remainder)
  else:
    pdiv = xDivRem(a, b, prem)

  #[ Set the signs.
       The quotient pdiv has the sign of a*b;
       the remainder prem has the sign of a,
       so a = b*z + r.]#
  if (a.sign == Negative) != (b.sign == Negative):
    pdiv.setSignNegative()
  if (a.sign == Negative) and not prem.zero():
    prem.setSignNegative()


proc lDivmod(v, w: PyIntObject, divRes, modRes: var PyIntObject): bool{.pyCFuncPragma.} =
  ## Python's returns -1 on failure, which is only to be Memory Alloc failure
  ## where nim will just `SIGSEGV`
  ## 
  ## returns w != 0
  result = true

  # Fast path for single-digit longs
  if v.digits.len == 1 and w.digits.len == 1:
    divRes = fast_floor_div(v, w, off)
    modRes = fast_mod(v, w, off)
    return

  # Perform long division and remainder
  if not tryDivrem(v, w, divRes, modRes): return false

  # Adjust signs if necessary
  if (modRes.sign == Negative and w.sign == Positive) or
     (modRes.sign == Positive and w.sign == Negative):
    modRes = modRes + w
    divRes = divRes - pyIntOne

# a**b
proc pow*(a, b: PyIntObject): PyIntObject =
  assert(not b.negative)
  if b.zero:
    return pyIntOne
  # we have checked b is not zero
  let new_b = b.floorDivNonZero pyIntTwo
  let half_c = pow(a, new_b)
  if b.digits[0] mod 2 == 1:
    return half_c * half_c * a
  else:
    return half_c * half_c


#[
proc newPyInt(i: int): PyIntObject =
  var ii: int
  if i < 0:
    result = newPyIntSimple()
    result.sign = Negative
    ii = (not i) + 1
  elif i == 0:
    return pyIntZero
  else:
    result = newPyIntSimple()
    result.sign = Positive
    ii = i
  result.digits.add uint32(ii)
  result.digits.add uint32(ii shr 32)
  result.normalize
]#
const PyLongBaseSet* = {0, 2..36}

template check_max_str_digits_with_msg(fail_cond; errMsg){.dirty.} =
  bind PyInterpreterState_GET_long_state
  let max_str_digits = PyInterpreterState_GET_long_state().max_str_digits
  if max_str_digits > 0 and fail_cond:
    return newValueError newPyAscii errMsg

template fromStrAux[C: char|Rune](result: var PyIntObject; s: openArray[C]; i: var int; base: uint8#[PyLongBase]#; checkThreshold: static[bool]; cToDigit) {.dirty.} =
  bind inplaceMul, inplaceAdd, normalize
  bind check_max_str_digits_with_msg, PY_INT_MAX_STR_DIGITS_THRESHOLD, MAX_STR_DIGITS_errMsg_to_int
  result = newPyIntSimple()
  # assume s not empty
  result.digits.add 0
  var pre = '\0'
  while i < s.len:
    when checkThreshold:
      if i > PY_INT_MAX_STR_DIGITS_THRESHOLD:
        check_max_str_digits_with_msg i > max_str_digits, MAX_STR_DIGITS_errMsg_to_int(max_str_digits, i)
    let c = s[i]
    if c == C'_':
      # Double underscore not allowed.
      if pre == C'_':
        break
    else:
      inplaceMul(result, base)
      inplaceAdd(result, cToDigit)
    pre = c
    i.inc

  normalize(result)

template isspace(c: char): bool = c.isSpaceAscii
template fromStrImpl[C: char|Rune](result: var PyIntObject; s: openArray[C]; i: var int; base: var uint8#[PyLongBase]#; checkThreshold: static[bool]; errInvStr; cToDigit) {.dirty.} =
  bind fromStrAux, isspace
  var sign: IntSign = Positive
  let L = s.len
  template chkIdx =
    if i == L: return
  
  template incIdx =
    i.inc
    chkIdx
  chkIdx
  # strip leading whitespace
  while isspace s[i]: incIdx

  var error_if_nonzero = false
  var cur: C
  template stcur = cur = s[i]
  stcur
  if cur == C'+': incIdx
  elif cur == C'-':
    incIdx
    sign = Negative

  template curIs(a, b): bool = cur == a or cur == b
  template preHex: bool = curIs(C'x', C'X')
  template preOct: bool = curIs(C'o', C'O')
  template preBin: bool = curIs(C'b', C'B')
  stcur

  var pre0 = cur == C'0'

  res = pyIntZero
  if base == 0:
    if not pre0: base = 10
    else:
      # may be a simple "0"
      incIdx  # may `return` here, if is "0"
      stcur
      base = if preHex: 16
      elif preOct: 8
      elif preBin: 2
      else:
        #["old" (C-style) octal literal, now invalid.
              it might still be zero though]#
        error_if_nonzero = true
        10
      dec i

  if pre0 and (incIdx; stcur; (  # may `return` here, if is "0"
    base == 16 and preHex or
    base == 8  and preOct or
    base == 2  and preBin
  )):
    incIdx
    # One underscore allowed here.
    stcur
    if cur == C'_':
      incIdx

  fromStrAux(result, s, i, base, checkThreshold, cToDigit)

  # Allow only trailing whitespace after `end`
  while true:
    if i < L and isspace s[i]:
      i.inc
    else:
      break

  let zero = result.digits.len == 0
  if error_if_nonzero:
    #[reset the base to 0, else the exception message
      doesn't make too much sense]#
    base = 0
    if not zero:
      errInvStr
    #[there might still be other problems, therefore base
    remains zero here for the same reason]#
  if zero:
    result.sign = Zero
  else:
    result.sign = sign


proc fromStr*[C: char|Rune](s: openArray[C]; res: var PyIntObject): int =
  ## with `base = 0` (a.k.a. support prefix like 0b)
  ## and ignore `sys.flags.int_max_str_digits`
  template err = return
  var base = 0u8
  res.fromStrImpl(s, result, base, false, err):
    when C is char:
      if c not_in Digits: err
      Digit(c) - Digit('0')
    else:
      var d: Digit
      c.decimalItOr:
        d = cast[Digit](it)
      do: err
      d
proc fromStr*[C: char|Rune](s: openArray[C]): PyIntObject{.raises: [ValueError].} =
  ## This ignores `sys.flags.int_max_str_digits`
  if s.fromStr(result) != s.len:
    raise newException(ValueError, "could not convert string to int")


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

proc fromStrWithValidBase[C: char](res: var PyIntObject; s: openArray[C]; nParsed: var int; base: int): PyBaseErrorObject =
  template err{.dirty.} =
    let strObj = newPyStr(s)
    retIfExc PyObject strObj
    retInvIntCall strObj, base
  var base = cast[uint8](base)
  res.fromStrImpl(s, nParsed, base, true, err):
    Digit c.digitOr(base, err)

proc fromStr*[C: char](res: var PyIntObject; s: openArray[C]; nParsed: var int): PyBaseErrorObject =
  res.fromStrWithValidBase s, nParsed, 10

proc fromStr*[C: char](res: var PyIntObject; s: openArray[C]; nParsed: var int; base: int): PyBaseErrorObject =
  if base != 0 and base < 2 or base > 36:
    invBaseRet
  res.fromStrWithValidBase(s, nParsed, base)

proc PyLong_FromString*[C: char](s: openArray[C]; nParsed: var int; base: int = 10): PyObject =
  var res: PyIntObject
  result = res.fromStr(s, nParsed, base)
  if result.isNil: result = res

proc format_binary*(a: PyIntObject, base: uint8, alternate: bool, v: var string): PyBaseErrorObject =
  ## long_format_binary
  assert base in {2u8, 8, 16}

  let
    size_a = a.digitCount
    high_a = size_a - 1
  let bits = case base
  of 16: 4
  of 8: 3
  of 2: 1
  else: unreachable
  let negative = a.negative
  var sz: int
  if size_a == 0:
    v = "0"
    return
  else:
    # Ensure overflow doesn't occur during computation of sz.
    if size_a > int.high - 3 div PyLong_SHIFT:
      return newOverflowError newPyAscii"int too large to format"
    {.push overflowChecks: off.}
    let size_a_in_bits = (high_a) * PyLong_SHIFT + bit_length(a.digits[high_a])
    # Allow 1 character for a '-' sign.
    sz = negative.int + (size_a_in_bits + (bits - 1)) div bits
    {.pop.}
  if alternate: sz += 2
  v = (when declared(newStringUninit): newStringUninit else: newString)(sz)

  template WRITE_DIGITS(p) =
    # JRH: special case for power-of-2 bases
    var accum = TwoDigits 0
    var accumbits = 0  # # of bits in accum
    for i in 0..<size_a:
      accum = accum or ((TwoDigits a.digits[i]) shl accumbits)
      accumbits += PyLong_SHIFT
      assert accumbits >= bits
      while true:
        var cdigit = cast[uint8](accum and (base - 1))
        cdigit += (if cdigit < 10: uint8'0' else: 87#[uint8('a')-10]#)
        *--cast[char](cdigit)
        accumbits -= bits
        accum = accum shr bits
        if not (
          if i < high_a: accumbits >= bits
          else: accum > 0): break
    if alternate:
      case bits
      of 4: *--'x'
      of 3: *--'o'
      else: *--'b' # base == 2
      *--'0'
    if negative: *--'-'

  var p = sz
  template `*--`(c) =
    p.dec
    v[p] = c

  WRITE_DIGITS p
  assert p == 0

proc fill(result: var string, i: PyIntObject) =
  if i.zero:
    result = "0"
    return
  var ii = i.copy()
  var r: Digit
  while true:
    ii = ii.divRem1(10, r)
    result.add(char(r + Digit('0')))
    if ii.digits.len == 0:
      break
  #strSeq.add($i.digits)
  if i.negative:
    result.add '-'
  result.reverse

proc length_hint(a: PyIntObject): int = a.digitCount * PyLong_DECIMAL_SHIFT
method `$`*(i: PyIntObject): string{.raises: [].} =
  ## this ignores `sys.flags.int_max_str_digits`,
  ##  and may raises `OverflowDefect` if `i` contains too many digits
  result = newStringOfCap(i.length_hint)
  result.fill i

proc toStringCheckThreshold*(a: PyIntObject, v: var string): PyBaseErrorObject{.raises: [].} =
  ## this respects `sys.flags.int_max_str_digits`
  template check_max_str_digits(fail_cond){.dirty.} =
    check_max_str_digits_with_msg fail_cond, MAX_STR_DIGITS_errMsg_to_str(max_str_digits)
  let size_a = a.digitCount
  if size_a >= 10 * PY_INT_MAX_STR_DIGITS_THRESHOLD div (3 * PyLong_SHIFT) + 2:
    check_max_str_digits(
       max_str_digits div (3 * PyLong_SHIFT) <= ((size_a - 11) div 10)
    )
  let negative = a.negative
  #let size_hint = size_a.length_hint
  #let scratch = newPyIntOfLen size_hint
  v = $a
  let strlen = v.len
  if strlen > PY_INT_MAX_STR_DIGITS_THRESHOLD:
    check_max_str_digits strlen - int(negative) > max_str_digits

proc format*(i: PyIntObject, base: uint8, s: var string): PyBaseErrorObject =
  # `_PyLong_Format`
  # `s` is a `out` param
  if base == 10: toStringCheckThreshold(i, s)
  else: format_binary(i, base, true, s)


proc newPyInt*[C: char](smallInt: C): PyIntObject =
  newPyInt int smallInt  # TODO

proc newPyInt*[C: Rune|char](str: openArray[C]): PyIntObject = 
  fromStr(str)

proc newPyInt*(dval: float): PyObject =
  ## `PyLong_FromDouble`
  #[
	  Try to get out cheap if this fits in a long. When a finite value of real
    floating type is converted to an integer type, the value is truncated
    toward zero. If the value of the integral part cannot be represented by
    the integer type, the behavior is undefined. Thus, we must check that
    value is in range (LONG_MIN - 1, LONG_MAX + 1). If a long has more bits
    of precision than a double, casting LONG_MIN - 1 to double may yield an
    approximation, but LONG_MAX + 1 is a power of two and can be represented
    as double exactly (assuming FLT_RADIX is 2 or 16), so for simplicity
    check against (-(LONG_MAX + 1), LONG_MAX + 1).
	]#
  case dval.classify
  of fcInf, fcNegInf:
    return newOverflowError(newPyAscii"cannot convert float infinity to integer")
  of fcNan:
    return newValueError(newPyAscii"cannot convert float NaN to integer")
  else: discard

  const int_max = float int.high.uint + 1
  if -int_max <= dval and dval <= int_max:
    return newPyInt(int dval)

  var dval = dval
  var neg = false
  if dval < 0.0:
    neg = true
    dval = -dval

  var expo: int
  var frac = frexp(dval, expo)  # dval = frac*2**expo; 0.0 <= frac < 1.0
  assert expo > 0
  let expo1s = expo - 1

  let ndig = expo1s div PyLong_SHIFT + 1
  let res = newPyIntOfLenUninit(ndig)

  when declared(ldexp):
    # NIMPYLIB:ldexp
    frac = ldexp(frac, expo1s mod PyLong_SHIFT + 1)
    for i in countdown(ndig-1, 0):
      let bits = Digit(frac)
      res.digits[i] = bits
      frac -= float(bits)
      frac = ldexp(frac, PyLong_SHIFT)
  else:
    discard frac
    let fmaxValue = float high Digit
    #while dval >= 1.0:
    for i in countup(0, ndig-1):
      let digit = Digit(dval mod fmaxValue)

      #res.digits.add digit
      res.digits[i] = digit
      dval = dval / fmaxValue
    res.normalize()

  res.sign = if neg:
    Negative
  else:
    Positive
  res

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

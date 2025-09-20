import tables
import algorithm
import hashes
import macros
import strutils
import math
import std/typetraits

import ../numobjects_comm
export intobject_decl except Digit, TwoDigits, SDigit, digitBits, truncate,
 IntSign
import ./[
  bit_length, bit_length_util, shift, signbit,
  fromStrUtils, utils,
]
export bit_length, signbit
import ../../stringobject/strformat
import ../../../Modules/unicodedata/[decimal, space]


type STwoDigit = SDigit

const maxValue = TwoDigits(high(Digit)) + 1

template demote(x: TwoDigits): Digit =
  Digit(x shr digitBits)

export pyIntZero, pyIntOne, pyIntTen
let pyIntTwo = newPyInt(2)

using self: PyIntObject


# assuming all positive, return a - b
proc doCompare(a, b: PyIntObject): IntSign {. cdecl .} =
  if a.digits.len < b.digits.len:
    return Negative
  if a.digits.len > b.digits.len:
    return Positive
  for i in countdown(a.digits.len-1, 0):
    let ad = a.digits[i]
    let bd = b.digits[i]
    if ad < bd:
      return Negative
    elif ad == bd:
      continue
    else:
      return Positive
  return Zero


proc inplaceAdd(a: PyIntObject, b: Digit) =
  var carry = TwoDigits(b)
  for i in 0..<a.digits.len:
    if carry == 0:
      return
    carry += TwoDigits(a.digits[i])
    a.digits[i] = truncate(carry)
    carry = carry.demote
  if TwoDigits(0) < carry:
    a.digits.add truncate(carry)


# assuming all positive, return a + b
proc doAdd(a, b: PyIntObject): PyIntObject =
  if a.digits.len < b.digits.len:
    return doAdd(b, a)
  var carry = TwoDigits(0)
  result = newPyIntSimple()
  for i in 0..<a.digits.len:
    if i < b.digits.len:
      # can't use inplace-add, gh-10697
      carry = carry + TwoDigits(b.digits[i])
    carry += TwoDigits(a.digits[i])
    result.digits.add truncate(carry)
    carry = carry.demote
  if TwoDigits(0) < carry:
    result.digits.add truncate(carry)

# assuming all positive, return a - b
proc doSub(a, b: PyIntObject): PyIntObject =
  result = newPyIntSimple()
  result.sign = Positive

  var borrow = false #Digit(0)

  # Ensure `a` is the larger of the two
  var larger = a
  var smaller = b
  var sizeA = larger.digits.len
  var sizeB = smaller.digits.len
  if sizeA < sizeB or (sizeA == sizeB and doCompare(a, b) == Negative):
    result.sign = Negative
    larger = b
    smaller = a
    swap sizeA, sizeB
  result.digits.setLen(sizeA)

  # Perform subtraction digit by digit
  for i in 0..<sizeB:
    let diff = TwoDigits(larger.digits[i]) - TwoDigits(smaller.digits[i]) - TwoDigits(borrow)
    result.digits[i] = truncate(diff)
    borrow = diff < 0

  for i in sizeB..<sizeA:
    let diff = TwoDigits(larger.digits[i]) - TwoDigits(borrow)
    result.digits[i] = truncate(diff)
    borrow = diff < 0

  # Normalize the result to remove leading zeros
  result.normalize()

  # Handle the sign of the result
  if result.digits.len == 0:
    result.sign = Zero

template doMulImpl(result, b; loopVar, loopIter, src, dst) =
  ## assuming all Positive
  var carry = TwoDigits(0)
  let tb = TwoDigits(b)
  for loopVar in loopIter:
    carry += TwoDigits(src) * tb
    dst = truncate(carry)
    carry = carry.demote
  if 0'u64 < carry:
    result.digits.add truncate(carry)

# assuming all Natural, return a * b
proc doMul(a: PyIntObject, b: Digit): PyIntObject =
  result = newPyIntOfLen(a.digits.len)
  result.doMulImpl(b, i, 0..<a.digits.len, a.digits[i], result.digits[i])

proc inplaceMul(a: var PyIntObject, b: Digit|uint8) =
  # assuming all Natural
  a.doMulImpl(b, d, a.digits.mitems, d, d)

proc doMul(a, b: PyIntObject): PyIntObject =
  if a.digits.len < b.digits.len:
    return doMul(b, a)
  var ints: seq[PyIntObject]
  for i, db in b.digits:
    let c = a.doMul(db)
    let zeros = newSeq[Digit](i)
    c.digits = zeros & c.digits
    ints.add c
  result = ints[0]
  for intObj in ints[1..^1]:
    result = result.doAdd(intObj)

proc `<`*(a, b: PyIntObject): bool =
  case a.sign
  of Negative:
    case b.sign
    of Negative:
      return doCompare(a, b) == Positive
    of Zero, Positive:
      return true
  of Zero:
    return b.sign == Positive
  of Positive:
    case b.sign
    of Negative, Zero:
      return false
    of Positive:
      return doCompare(a, b) == Negative

proc `<`*(aa: int, b: PyIntObject): bool =
  let a = newPyInt(aa)
  case a.sign
  of Negative:
    case b.sign
    of Negative:
      return doCompare(a, b) == Positive
    of Zero, Positive:
      return true
  of Zero:
    return b.sign == Positive
  of Positive:
    case b.sign
    of Negative, Zero:
      return false
    of Positive:
      return doCompare(a, b) == Negative

proc `==`*(a, b: PyIntObject): bool =
  if a.sign != b.sign:
    return false
  return doCompare(a, b) == Zero

proc `+`*(a, b: PyIntObject): PyIntObject =
  case a.sign
  of Negative:
    case b.sign
    of Negative:
      let c = doAdd(a, b)
      c.sign = Negative
      return c
    of Zero:
      return a
    of Positive:
      return doSub(b, a)
  of Zero:
    return b
  of Positive:
    case b.sign
    of Negative:
      return doSub(a, b)
    of Zero:
      return a
    of Positive:
      let c = doAdd(a, b)
      c.sign = Positive
      return c

proc `-`*(a, b: PyIntObject): PyIntObject =
  case a.sign
  of Negative:
    case b.sign
    of Negative:
      return doSub(b, a)
    of Zero:
      return a
    of Positive:
      let c = doAdd(a, b)
      c.sign = Negative
      return c
  of Zero:
    case b.sign
    of Negative:
      let c = b.copy()
      c.sign = Positive
      return c
    of Zero:
      return a
    of Positive:
      let c = b.copy()
      c.sign = Negative
      return c
  of Positive:
    case b.sign
    of Negative:
      let c = doAdd(a, b)
      c.sign = Positive
      return c
    of Zero:
      return a
    of Positive:
      return doSub(a, b)


proc `-`*(a: PyIntObject): PyIntObject =
  result = a.copy()
  result.sign = a.sign
  result.flipSign

proc abs*(self): PyIntObject =
  if self.negative: -self
  else: self

proc `*`*(a, b: PyIntObject): PyIntObject =
  case a.sign
  of Negative:
    case b.sign
    of Negative:
      let c = doMul(a, b)
      c.sign = Positive
      return c
    of Zero:
      return pyIntZero
    of Positive:
      let c = doMul(a, b)
      c.sign = Negative
      return c
  of Zero:
    return pyIntZero
  of Positive:
    case b.sign
    of Negative:
      let c = doMul(a, b)
      c.sign = Negative
      return c
    of Zero:
      return pyIntZero
    of Positive:
      let c = doMul(a, b)
      c.sign = Positive
      return c


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


template fromStrAux[C: char|Rune](result: var PyIntObject; s: openArray[C]; i: var int; base: uint8#[PyLongBase]#; cToDigit) {.dirty.} =
  bind inplaceMul, inplaceAdd, normalize
  result = newPyIntSimple()
  # assume s not empty
  result.digits.add 0
  while i < s.len:
    let c = s[i]
    if c != C'_':
      inplaceMul(result, base)
      inplaceAdd(result, cToDigit)
    i.inc

  normalize(result)

template isspace(c: char): bool = c.isSpaceAscii
template fromStrImpl[C: char|Rune](result: var PyIntObject; s: openArray[C]; i: var int; base: var uint8#[PyLongBase]#; err; cToDigit) {.dirty.} =
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

  fromStrAux(result, s, i, base, cToDigit)

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
      err
    #[there might still be other problems, therefore base
    remains zero here for the same reason]#
  if zero:
    result.sign = Zero
  else:
    result.sign = sign


proc fromStr*[C: char|Rune](s: openArray[C]; res: var PyIntObject): int =
  ## with `base = 0` (a.k.a. support prefix like 0b)
  template err = return
  var base = 0u8
  res.fromStrImpl(s, result, base, err):
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
  res.fromStrImpl(s, nParsed, base, err):
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

method `$`*(i: PyIntObject): string{.raises: [].} =
  if i.zero:
    return "0"
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

proc hash*(self: PyIntObject): Hash {. inline, cdecl .} = 
  result = hash(self.sign)
  for digit in self.digits:
    result = result xor hash(digit)


proc toSomeSignedIntUnsafe*[T: SomeSignedInt](pyInt: PyIntObject): T =
  ## XXX: the caller should take care of overflow
  ##  It raises `OverflowDefect` on non-danger build
  for i in countdown(pyInt.digits.high, 0):
    result = result shl digitBits
    result += T(pyInt.digits[i])
  if pyInt.sign == Negative:
    result *= -1

template PY_ABS_INT_MIN(T): untyped = cast[T.toUnsigned](T.low) ## \
## we cannot use `0u - cast[BiggestUInt](BiggestInt.low)` unless with rangeChecks:off

type PossibleBiggestDigit = uint32
static: assert digitBits <= 8 * sizeof PossibleBiggestDigit
func absToUInt*[U: uint32|uint64|BiggestUInt](pyInt: PyIntObject, x: var U): bool{.cdecl.} =
  ## EXT. unstable.
  ##
  ## ignore signbit.
  ## returns false on overflow

  #TODO:opt-long apply python/cpython@d754f75f42f040267d818ab804ada340f55e5925
  x = U 0
  var prev{.noInit.}: U
  for i in countdown(pyInt.digits.high, 0):
    prev = x
    x = (x shl digitBits) or U(pyInt.digits[i])
    if x shr digitBits != prev:
      return
  return true

func absToUInt*[U: uint|uint8|uint16](pyInt: PyIntObject, x: var U): bool{.cdecl.} =
  var t: PossibleBiggestDigit
  if not absToUInt(pyInt, t): return
  if t > PossibleBiggestDigit U.high: return
  x = cast[U](t)
  true

# can be used as `PyLong_AsInt64`, `PyLong_AsInt32`, etc
proc toSomeSignedInt*[I: SomeSignedInt](pyInt: PyIntObject, overflow: var IntSign): I =
  ## if overflow, `overflow` will be `IntSign.Negative` or `IntSign.Positive
  ##   (depending the sign of the argument)
  ##   and result be `-1`
  ##
  ## Otherwise, `overflow` will be `IntSign.Zero`
  overflow = Zero

  result = -1
  let sign = pyInt.sign

  var x{.noInit.}: BiggestUInt
  if not pyInt.absToUInt(x):
    overflow = sign
    return
  #[ Haven't lost any bits, but casting to long requires extra
    care (see comment above).]#
  if x <= BiggestUInt I.high:
    result = cast[I](x) * cast[I](sign)
  elif sign == Negative and x == PY_ABS_INT_MIN(I):
    result = I.low
  else:
    overflow = sign

proc toInt*(pyInt: PyIntObject, overflow: var IntSign): int =
  toSomeSignedInt[int] pyInt, overflow

proc toSomeUnsignedInt*[U: SomeUnsignedInt](pyInt: PyIntObject, overflow: var IntSign): U =
  ## like `toSomeSignedInt`<#toInt,PyIntObject,IntSign>`_ but for `uint`
  overflow = if pyInt.negative: Negative
  elif pyInt.absToUInt(result): Zero
  else: Positive
proc toUInt*(pyInt: PyIntObject, overflow: var IntSign): uint =
  ## like `toInt`<#toInt,PyIntObject,IntSign>`_ but for `uint`
  toSomeUnsignedInt[uint](pyInt, overflow)

proc toInt*(pyInt: PyIntObject, res: var int): bool =
  ## returns false on overflow (`x not_in int.low..int.high`)
  var ovf: IntSign
  res = pyInt.toInt(ovf)
  result = ovf == IntSign.Zero

proc toUInt*(pyInt: PyIntObject, res: var uint): bool =
  ## like `toInt`<#toInt,PyIntObject,int>`_ but for `uint`
  if pyInt.negative: false
  else: pyInt.absToUInt(res)

proc PyInt_OverflowCType*(ctypeName: string): PyOverflowErrorObject =
  ## EXT.
  ## used to construct OverflowError of `PyLong_As<ctypeName>`
  ## So no need to call `PyLong_AsXxx` but `toSomeXxInt`
  return newOverflowError(
      newPyAscii "Python int too large to convert to C " & ctypeName)

proc PyLong_AsSsize_t*(vv: PyIntObject, res: var int): PyOverflowErrorObject =
  ## returns nil if not overflow
  if not toInt(vv, res):
    return PyInt_OverflowCType"ssize_t"

proc PyLong_AsSize_t*(pyInt: PyIntObject, res: var uint): PyOverflowErrorObject =
  if pyInt.negative:
    newOverflowError(newPyAscii"can't convert negative value to unsigned int")
  elif pyInt.absToUInt res: nil
  else: PyInt_OverflowCType"size_t"

proc asLongAndOverflow*(vv: PyIntObject, ovlf: var bool): int{.inline.} =
  ## PyLong_AsLongAndOverflow
  ovlf = not toInt(vv, result)

template toIntOrRetOF*(vv: PyIntObject): int =
  ## a helper wrapper of `PyLong_AsSsize_t`
  ## `return` OverflowError for outer function
  var i: int
  let ret = PyLong_AsSsize_t(vv, i)
  if not ret.isNil: return ret
  i

template genLongAs(c, n){.dirty.} =
  proc `PyLong_As c`*(v: PyObject, res: var n): PyBaseErrorObject =
    if not v.ofPyIntObject:
      res = cast[n](-1)
      return newTypeError newPyAscii"an integer is required"
    `PyLong_As c`(PyIntObject v, res)

genLongAs Ssize_t, int
genLongAs Size_t, uint

proc newPyInt*[C: char](smallInt: C): PyIntObject =
  newPyInt int smallInt  # TODO

proc newPyInt*[C: Rune|char](str: openArray[C]): PyIntObject = 
  fromStr(str)



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

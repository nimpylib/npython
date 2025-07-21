# todo: split the file into 4:
#   intobject, floatobject, intobjectImpl, floatobjectImpl
import tables
import algorithm
import hashes
import parseutils
import macros
import strformat
import strutils
import math
import std/bitops
const BitPerByte = 8
proc bit_length*(self: SomeInteger): int =
  when defined(noUndefinedBitOpts):
    sizeof(x) * BitPerByte bitops.countLeadingZeroBits x
  else:
    1 + fastLog2(
      when self is SomeSignedInt: abs(self)
      else: self
    )


import pyobject
import exceptions
import boolobject
import stringobject
import ../Utils/utils
# this is a **very slow** bigint lib.
# Why reinvent such a bad wheel?
# because we seriously need low level control on our modules
# todo: make it a decent bigint module
#
# js can't process 64-bit int although nim has this type for js
when defined(js):
  type
    Digit = uint16
    TwoDigits = uint32
    SDigit = int32

  const digitBits = 16
    
  template truncate(x: TwoDigits): Digit =
    const mask = 0x0000FFFF
    Digit(x and mask)

else:
  type
    Digit = uint32
    TwoDigits = uint64
    SDigit = int64

  const digitBits = 32

  template truncate(x: TwoDigits): Digit =
    Digit(x)

type STwoDigit = SDigit


const maxValue = TwoDigits(high(Digit)) + 1
const sMaxValue = SDigit(high(Digit)) + 1

template demote(x: TwoDigits): Digit =
  Digit(x shr digitBits)


type IntSign = enum
  Negative = -1
  Zero = 0
  Positive = 1

declarePyType Int(tpToken):
  #v: BigInt
  #v: int
  sign: IntSign
  digits: seq[Digit]

#proc compatSign(op: PyIntObject): SDigit{.inline.} = cast[SDigit](op.sign)
# NOTE: CPython uses 0,1,2 for IntSign, so its `_PyLong_CompactSign` is `1 - sign`

#proc newPyInt(i: Digit): PyIntObject
proc newPyInt*(o: PyIntObject): PyIntObject =
  ## deep copy, returning a new object
  result = newPyIntSimple()
  result.sign = o.sign
  result.digits = o.digits

proc newPyInt*(i: Digit): PyIntObject =
  result = newPyIntSimple()
  if i != 0:
    result.digits.add i
    result.sign = Positive
  # can't be negative
  else:
    result.sign = Zero

proc newPyInt*[I: SomeSignedInt](i: I): PyIntObject =
  result = newPyIntSimple()
  var ui = abs(i)
  while ui != 0:
    result.digits.add Digit(
      when sizeof(I) <= sizeof(SDigit): ui
      else: ui mod I(sMaxValue)
    )
    ui = ui shr digitBits

  if i < 0:
    result.sign = Negative
  elif i == 0:
    result.sign = Zero
  else:
    result.sign = Positive

proc newPyIntOfLen(l: int): PyIntObject =
  ## `long_alloc`
  ## 
  ## result sign is `Positive` if l != 0; `Zero` otherwise
  result = newPyIntSimple()
  result.digits.setLen(l)
  if l != 0:
    result.sign = Positive

let pyIntZero* = newPyInt(0)
let pyIntOne* = newPyInt(1)
let pyIntTwo = newPyInt(2)
let pyIntTen* = newPyInt(10)

proc negative*(intObj: PyIntObject): bool {. inline .} =
  intObj.sign == Negative

proc zero*(intObj: PyIntObject): bool {. inline .} =
  intObj.sign == Zero

proc positive*(intObj: PyIntObject): bool {. inline .} =
  intObj.sign == Positive

proc copy(intObj: PyIntObject): PyIntObject =
  ## XXX: copy only digits (sign uninit!)
  let newInt = newPyIntSimple()
  newInt.digits = intObj.digits
  newInt

proc normalize(a: PyIntObject) =
  for i in 0..<a.digits.len:
    if a.digits[^1] == 0:
      discard a.digits.pop()
    else:
      break

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

# assuming all positive, return a * b
proc doMul(a: PyIntObject, b: Digit): PyIntObject =
  result = newPyIntSimple()
  var carry = TwoDigits(0)
  for i in 0..<a.digits.len:
    carry += TwoDigits(a.digits[i]) * TwoDigits(b)
    result.digits.add truncate(carry)
    carry = carry.demote
  if 0'u64 < carry:
    result.digits.add truncate(carry)
  
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

proc negate*(self: PyIntObject){.inline.} =
  self.sign = Negative

proc `-`*(a: PyIntObject): PyIntObject =
  result = a.copy()
  result.sign = IntSign(-int(a.sign))


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

proc tryRem(a, b: PyIntObject, prem: var PyIntObject): bool
proc lMod(v, w: PyIntObject, modRes: var PyIntObject): bool =
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

let divZeroError = newPyAscii"division by zero"
template retZeroDiv =
  return newZeroDivisionError divZeroError

proc `%`*(a, b: PyIntObject): PyObject =
  var res: PyIntObject
  if lMod(a, b, res):
    retZeroDiv
  result = res

proc lDivmod(v, w: PyIntObject, divRes, modRes: var PyIntObject): bool

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

proc `//`*(a, b: PyIntObject): PyObject =
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

proc vLShift(z, a: var seq[Digit], m: int, d: int): Digit =
  ## Shift digit vector `a[0:m]` left by `d` bits, with 0 <= d < digitBits.
  ## Put the result in `z[0:m]`, and return the `d` bits shifted out of the top.
  assert d >= 0 and d < digitBits
  var carry: Digit = 0
  for i in 0..<m:
    let shifted = (TwoDigits(a[i]) shl d) or TwoDigits(carry)
    z.add truncate(shifted)
    carry = truncate(shifted shr digitBits)
  return carry

proc vRShift(z, a: var seq[Digit], m: int, d: int): Digit =
  ## Shift digit vector `a[0:m]` right by `d` bits, with 0 <= d < digitBits.
  ## Put the result in `z[0:m]`, and return the `d` bits shifted out of the bottom.
  assert d >= 0 and d < digitBits
  var carry: Digit = 0
  let mask = (Digit(1) shl d) - 1

  for i in countdown(m - 1, 0):
    let acc = (TwoDigits(carry) shl digitBits) or TwoDigits(a[i])
    carry = Digit(acc and mask)
    z[i] = Digit(acc shr d)

  return carry
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

proc tryRem(a, b: PyIntObject, prem: var PyIntObject): bool =
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
    prem.negate()

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
    pdiv.negate()
  if (a.sign == Negative) and not prem.zero():
    prem.negate()


proc lDivmod(v, w: PyIntObject, divRes, modRes: var PyIntObject): bool =
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
proc pow(a, b: PyIntObject): PyIntObject =
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
proc fromStr[C: char|Rune](s: openArray[C]): PyIntObject =
  result = newPyIntSimple()
  var sign = s[0] == C'-'
  # assume s not empty
  result.digits.add 0
  for i in (sign.int)..<s.len:
    result = result.doMul(10)
    let c = s[i]
    result.inplaceAdd Digit(c) - Digit('0')
  result.normalize
  if sign:
    result.sign = Negative
  else:
    if result.digits.len == 0:
      result.sign = Zero
    else:
      result.sign = Positive

method `$`*(i: PyIntObject): string =
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

declarePyType Float(tpToken):
  v: float

method `$`*(f: PyFloatObject): string = 
  $f.v

proc toInt*(pyInt: PyIntObject): int = 
  # XXX: the caller should take care of overflow
  for i in countdown(pyInt.digits.len-1, 0):
    result = result shl digitBits
    result += int(pyInt.digits[i])
  if pyInt.sign == Negative:
    result *= -1


proc toFloat*(pyInt: PyIntObject): float = 
  parseFloat($pyInt)


proc newPyInt*[C: Rune|char](str: openArray[C]): PyIntObject = 
  fromStr(str)

proc newPyFloat*(pyInt: PyIntObject): PyFloatObject = 
  result = newPyFloatSimple()
  result.v = pyInt.toFloat 


proc newPyFloat*(v: float): PyFloatObject = 
  result = newPyFloatSimple()
  result.v = v


template intBinaryTemplate(op, methodName: untyped, methodNameStr:string) = 
  if other.ofPyIntObject:
    #result = newPyInt(self.v.op PyIntObject(other).v)
    result = self.op PyIntObject(other)
  elif other.ofPyFloatObject:
    let newFloat = newPyFloat(self)
    result = newFloat.callMagic(methodName, other)
  else:
    let msg = methodnameStr & fmt" not supported by int and {other.pyType.name}"
    result = newTypeError(newPyAscii msg)


implIntMagic add:
  intBinaryTemplate(`+`, add, "+")


implIntMagic sub:
  intBinaryTemplate(`-`, sub, "-")


implIntMagic mul:
  intBinaryTemplate(`*`, mul, "*")


implIntMagic trueDiv:
  let casted = newPyFloat(self) ## XXX: TODO: ref long_true_divide
  casted.callMagic(trueDiv, other)


implIntMagic floorDiv:
 if other.ofPyIntObject:
   self // PyIntObject(other)
 elif other.ofPyFloatObject:
   let newFloat = newPyFloat(self)
   return newFloat.callMagic(floorDiv, other)
 else:
   return newTypeError(newPyString fmt"floor divide not supported by int and {other.pyType.name}")

implIntMagic Mod:
  intBinaryTemplate(`%`, pow, "%")

implIntMagic pow:
  intBinaryTemplate(pow, pow, "**")


implIntMagic positive:
  self

implIntMagic negative: 
  -self

implIntMagic bool:
  if self.zero:
    pyFalseObj
  else:
    pyTrueObj


implIntMagic lt:
  if other.ofPyIntObject:
    if self < PyIntObject(other):
      result = pyTrueObj
    else:
      result = pyFalseObj
  elif other.ofPyFloatObject:
    result = other.callMagic(ge, self)
  else:
    let msg = fmt"< not supported by int and {other.pyType.name}"
    result = newTypeError(newPyStr msg)


implIntMagic eq:
  if other.ofPyIntObject:
    if self == PyIntObject(other):
      result = pyTrueObj
    else:
      result = pyFalseObj
  elif other.ofPyFloatObject:
    result = other.callMagic(eq, self)
  elif other.ofPyBoolObject:
    if self == pyIntOne:
      result = other
    else:
      result = other.callMagic(Not)
  else:
    let msg = fmt"== not supported by int and {other.pyType.name}"
    result = newTypeError(newPyStr msg)

implIntMagic str:
  newPyAscii($self)


implIntMagic repr:
  newPyAscii($self)


implIntMagic hash:
  self

implIntMagic New:
  checkArgNum(2)
  let arg = args[1]
  case arg.pyType.kind
  of PyTypeToken.Int:
    return arg
  of PyTypeToken.Float:
    let iStr = $cast[PyFloatObject](arg).v
    return newPyInt(iStr.split(".")[0])
  of PyTypeToken.Str:
    let str = cast[PyStrObject](arg).str
    try:
      return str.doBothKindOk newPyInt
    except ValueError:
      let msg = fmt"invalid literal for int() with base 10: '{str}'"
      return newValueError(newPyStr msg)
  of PyTypeToken.Bool:
    if cast[PyBoolObject](arg).b:
      return newPyInt(1)
    else:
      return newPyInt(0)
  else:
    return newTypeError(newPyStr fmt"Int argument can't be '{arg.pyType.name}'")

template castOtherTypeTmpl(methodName) = 
  var casted {. inject .} : PyFloatObject
  if other.ofPyFloatObject:
    casted = PyFloatObject(other)
  elif other.ofPyIntObject:
    casted = newPyFloat(PyIntObject(other))
  else:
    let msg = methodName & fmt" not supported by float and {other.pyType.name}"
    return newTypeError(newPyStr msg)

macro castOther(code:untyped):untyped = 
  let fullName = code.name.strVal
  let d = fullName.skipUntil('P') # add'P'yFloatObj, luckily there's no 'P' in magics
  let methodName = fullName[0..<d]
  code.body = newStmtList(
    getAst(castOtherTypeTmpl(methodName)),
    code.body
  )
  code


implFloatMagic add, [castOther]:
  newPyFloat(self.v + casted.v)


implFloatMagic sub, [castOther]:
  newPyFloat(self.v - casted.v)


implFloatMagic mul, [castOther]:
  newPyFloat(self.v * casted.v)


implFloatMagic trueDiv, [castOther]:
  newPyFloat(self.v / casted.v)

proc floorDivNonZero(a, b: PyFloatObject): PyFloatObject =
  newPyFloat(floor(a.v / b.v))

proc floorModNonZero(a, b: PyFloatObject): PyFloatObject =
  newPyFloat(floorMod(a.v, b.v))

template genDivOrMod(dm, mag){.dirty.} =
  proc `floor dm`(a, b: PyFloatObject): PyObject =
    if b.v == 0:
      retZeroDiv
    `floor dm NonZero` a, b

  implFloatMagic mag, [castOther]:
    `floor dm` self, casted

genDivOrMod Div, floorDiv
genDivOrMod Mod, Mod

proc divmodNonZero*(a, b: PyFloatObject): tuple[d, m: PyFloatObject] =
  ## export for builtins.divmod
  result.d = a.floorDivNonZero b
  result.m = a.floorModNonZero b

proc divmod*(a, b: PyFloatObject): tuple[d, m: PyFloatObject] =
  if b.v == 0.0:
    raise newException(ValueError, "division by zero")
  divmodNonZero(a, b)


implFloatMagic pow, [castOther]:
  newPyFloat(self.v.pow(casted.v))


implFloatMagic positive:
  self

implFloatMagic negative:
  newPyFloat(-self.v)


implFloatMagic bool:
  if self.v == 0:
    return pyFalseObj
  else:
    return pyTrueObj


implFloatMagic lt, [castOther]:
  if self.v < casted.v:
    return pyTrueObj
  else:
    return pyFalseObj


implFloatMagic eq, [castOther]:
  if self.v == casted.v:
    return pyTrueObj
  else:
    return pyFalseObj


implFloatMagic gt, [castOther]:
  if self.v > casted.v:
    return pyTrueObj
  else:
    return pyFalseObj


implFloatMagic str:
  newPyAscii($self)


implFloatMagic repr:
  newPyAscii($self)

implFloatMagic hash:
  newPyInt(hash(self.v))


# used in list and tuple
template getIndex*(obj: PyIntObject, size: int, sizeOpIdx: untyped = `<=`): int =
  # todo: if overflow, then thrown indexerror
  var idx = obj.toInt
  if idx < 0:
    idx = size + idx
  if (idx < 0) or (sizeOpIdx(size, idx)):
    let msg = "index out of range. idx: " & $idx & ", len: " & $size
    return newIndexError newPyAscii(msg)
  idx


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
  let a = fromStr("100000000000")
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

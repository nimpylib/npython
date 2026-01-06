
import ../numobjects_comm
import ./[utils, ops_basic_private]

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

# assuming all Natural, return a * b
proc doMul(a: PyIntObject, b: Digit): PyIntObject =
  result = newPyIntOfLen(a.digits.len)
  result.doMulImpl(b, i, 0..<a.digits.len, a.digits[i], result.digits[i])


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

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

import pyobject
import exceptions
import boolobject
import stringobject
import ../Utils/utils

# this is a **very slow** bigint lib, div support is not complete.
# Why reinvent such a bad wheel?
# because we seriously need low level control on our modules
# todo: make it a decent bigint module
#
# js can't process 64-bit int although nim has this type for js
when defined(js):
  type
    Digit = uint16
    TwoDigits = uint32

  const digitBits = 16
    
  proc `$`(i: uint16|uint32): string = 
    $int(i)

  template truncate(x: TwoDigits): Digit =
    const mask = 0x0000FFFF
    Digit(x and mask)

else:
  type
    Digit = uint32
    TwoDigits = uint64

  const digitBits = 32

  template truncate(x: TwoDigits): Digit =
    Digit(x)

const maxValue = TwoDigits(high(Digit)) + 1

template promote(x: Digit): TwoDigits =
  TwoDigits(x) shl digitBits

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

#proc newPyInt(i: Digit): PyIntObject
proc newPyInt*(i: int): PyIntObject

# currently avoid using setLen because of gh-10651
proc setXLen(intObj: PyIntObject, l: int) =
  if intObj.digits.len == 0:
    intObj.digits = newSeq[Digit](l)
  else:
    intObj.digits.setLen(l)

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


proc doDiv(n, d: PyIntObject): (PyIntObject, PyIntObject) =
  var
    nn = n.digits.len
    dn = d.digits.len
  assert nn != 0

  if nn < dn:
    return (pyIntZero, n)
  elif dn == 1:
    let dd = d.digits[0]
    let q = newPyIntSimple()
    var rr: Digit
    q.setXLen(n.digits.len)

    for i in countdown(n.digits.high, 0):
      let tmp = TwoDigits(n.digits[i]) + rr.promote
      q.digits[i] = truncate(tmp div TwoDigits(dd))
      rr = truncate(tmp mod Twodigits(dd))

    q.normalize()
    let r = newPyIntSimple()
    r.digits.add rr
    return (q, r)
  else:
    assert nn >= dn and dn >= 2
    raise newException(IntError, "")


proc `div`*(a, b: PyIntObject): PyIntObject =
  case a.sign
  of Negative:
    case b.sign
    of Negative:
      let (q, r) = doDiv(a, b)
      if q.digits.len == 0:
        q.sign = Zero
      else:
        q.sign = Positive
      return q
    of Zero:
      assert false
    of Positive:
      let (q, r) = doDiv(a, b)
      if q.digits.len == 0:
        q.sign = Zero
      else:
        q.sign = Negative
      return q
  of Zero:
    return pyIntZero
  of Positive:
    case b.sign
    of Negative:
      let (q, r) = doDiv(a, b)
      if q.digits.len == 0:
        q.sign = Zero
      else:
        q.sign = Negative
      return q
    of Zero:
      assert false
    of Positive:
      let (q, r) = doDiv(a, b)
      if q.digits.len == 0:
        q.sign = Zero
      else:
        q.sign = Positive
      return q

# a**b
proc pow(a, b: PyIntObject): PyIntObject =
  assert(not b.negative)
  if b.zero:
    return pyIntOne
  let new_b = b div pyIntTwo
  let half_c = pow(a, new_b)
  if b.digits[0] mod 2 == 1:
    return half_c * half_c * a
  else:
    return half_c * half_c

#[
proc newPyInt(i: Digit): PyIntObject =
  result = newPyIntSimple()
  if i != 0:
    result.digits.add i
  # can't be negative
  if i == 0:
    result.sign = Zero
  else:
    result.sign = Positive

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
proc fromStr(s: string): PyIntObject =
  result = newPyIntSimple()
  var start = 0
  var sign: IntSign
  # assume s not empty
  if s[0] == '-':
    start = 1
  result.digits.add 0
  for i in start..<s.len:
    result = result.doMul(10)
    let c = s[i]
    result.inplaceAdd Digit(ord(c) - ord('0'))
  result.normalize
  if s[0] == '-':
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
  var r: PyIntObject
  while true:
    (ii, r) = ii.doDiv pyIntTen
    result.add(char(r.digits[0] + Digit('0')))
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


proc newPyInt*(str: string): PyIntObject = 
  fromStr(str)

proc newPyInt*(i: int): PyIntObject = 
  result = newPyIntSimple()
  var ui = abs(i)
  while ui != 0:
    result.digits.add Digit(ui mod int(maxValue))
    ui = ui shr digitBits

  if i < 0:
    result.sign = Negative
  elif i == 0:
    result.sign = Zero
  else:
    result.sign = Positive


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
    result = newTypeError(msg)


implIntMagic add:
  intBinaryTemplate(`+`, add, "+")


implIntMagic sub:
  intBinaryTemplate(`-`, sub, "-")


implIntMagic mul:
  intBinaryTemplate(`*`, mul, "*")


implIntMagic trueDiv:
  let casted = newPyFloat(self)
  casted.callMagic(trueDiv, other)


implIntMagic floorDiv:
 if other.ofPyIntObject:
   let intOther = PyIntObject(other)
   if intOther.zero:
     return newZeroDivisionError()
   try:
     return self.div PyIntObject(other)
   except IntError:
     return newValueError("big int operation not implemented")
 elif other.ofPyFloatObject:
   let newFloat = newPyFloat(self)
   return newFloat.callMagic(floorDiv, other)
 else:
   return newTypeError(fmt"floor divide not supported by int and {other.pyType.name}")

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
    result = newTypeError(msg)


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
    result = newTypeError(msg)

implIntMagic str:
  newPyString($self)


implIntMagic repr:
  newPyString($self)


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
      return newPyInt(str)
    except ValueError:
      let msg = fmt"invalid literal for int() with base 10: '{str}'"
      return newValueError(msg)
  of PyTypeToken.Bool:
    if cast[PyBoolObject](arg).b:
      return newPyInt(1)
    else:
      return newPyInt(0)
  else:
    return newTypeError(fmt"Int argument can't be '{arg.pyType.name}'")

template castOtherTypeTmpl(methodName) = 
  var casted {. inject .} : PyFloatObject
  if other.ofPyFloatObject:
    casted = PyFloatObject(other)
  elif other.ofPyIntObject:
    casted = newPyFloat(PyIntObject(other))
  else:
    let msg = methodName & fmt" not supported by float and {other.pyType.name}"
    return newTypeError(msg)

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


implFloatMagic floorDiv, [castOther]:
  newPyFloat(floor(self.v / casted.v))


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
  newPyString($self)


implFloatMagic repr:
  newPyString($self)

implFloatMagic hash:
  newPyInt(hash(self.v))


# used in list and tuple
template getIndex*(obj: PyIntObject, size: int): int = 
  # todo: if overflow, then thrown indexerror
  var idx = obj.toInt
  if idx < 0:
    idx = size + idx
  if (idx < 0) or (size <= idx):
    let msg = "index out of range. idx: " & $idx & ", len: " & $size
    return newIndexError(msg)
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


import std/hashes
import std/typetraits
import ../numobjects_comm
export intobject_decl except Digit, TwoDigits, SDigit, digitBits, truncate,
 IntSign
import ./[
  decl, bit_length,
]
export bit_length, signbit, decl
import ../../../Include/internal/pycore_int
export PY_INT_MAX_STR_DIGITS_THRESHOLD, PY_INT_DEFAULT_MAX_STR_DIGITS

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
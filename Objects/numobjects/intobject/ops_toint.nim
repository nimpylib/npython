
from std/hashes import Hash
import ../numobjects_comm
export intobject_decl except Digit, TwoDigits, SDigit, digitBits, truncate,
 IntSign
import ./[
  decl, bit_length,
]
import pkg/intobject/ops_toint
export bit_length, signbit, decl
import ../../../Include/internal/pycore_int
export PY_INT_MAX_STR_DIGITS_THRESHOLD, PY_INT_DEFAULT_MAX_STR_DIGITS

proc hash*(self: PyIntObject): Hash {. inline, cdecl .} = hash(self.v)

proc toSomeSignedIntUnsafe*[T: SomeSignedInt](pyInt: PyIntObject): T =
  ## XXX: the caller should take care of overflow
  ##  It raises `OverflowDefect` on non-danger build
  pyInt.v.toSomeSignedIntUnsafe[:T]()

func absToUInt*(pyInt: PyIntObject, x: var SomeUnsignedInt): bool{.inline.} =
  ## EXT. unstable.
  ##
  ## ignore signbit.
  ## returns false on overflow
  pyInt.v.absToUInt(x)

# can be used as `PyLong_AsInt64`, `PyLong_AsInt32`, etc
proc toSomeSignedInt*[I: SomeSignedInt](pyInt: PyIntObject, overflow: var IntSign): I =
  ## if overflow, `overflow` will be `IntSign.Negative` or `IntSign.Positive
  ##   (depending the sign of the argument)
  ##   and result be `-1`
  ##
  ## Otherwise, `overflow` will be `IntSign.Zero`
  pyInt.v.toSomeSignedInt[:I](overflow)

proc toInt*(pyInt: PyIntObject, overflow: var IntSign): int =
  toSomeSignedInt[int] pyInt, overflow

proc toSomeUnsignedInt*[U: SomeUnsignedInt](pyInt: PyIntObject, overflow: var IntSign): U =
  ## like `toSomeSignedInt`<#toInt,PyIntObject,IntSign>`_ but for `uint`
  pyInt.v.toSomeUnsignedInt[:U](overflow)

proc toUInt*(pyInt: PyIntObject, overflow: var IntSign): uint =
  ## like `toInt`<#toInt,PyIntObject,IntSign>`_ but for `uint`
  toSomeUnsignedInt[uint](pyInt, overflow)

proc toInt*(pyInt: PyIntObject, res: var int): bool =
  ## returns false on overflow (`x not_in int.low..int.high`)
  pyInt.v.toInt(res)

proc toUInt*(pyInt: PyIntObject, res: var uint): bool =
  ## like `toInt`<#toInt,PyIntObject,int>`_ but for `uint`
  pyInt.v.toUInt(res)

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
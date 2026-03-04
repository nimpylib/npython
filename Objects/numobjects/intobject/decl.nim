

when defined(nimPreviewSlimSystem):
  import std/assertions
  export assertions

# Why not uses bigints and so on
# because we seriously need low level control on our modules
import ../../pyobject
import pkg/intobject/decl
# only export for ./intobject
export Digit, TwoDigits, SDigit, digitBits, truncate,
  IntSign, PyLong_SHIFT, PyLong_DECIMAL_SHIFT, PyLong_DECIMAL_BASE
const digitPyLong_DECIMAL_BASE* = Digit PyLong_DECIMAL_BASE

declarePyType Int(tpToken):
  #v: BigInt
  #v: int
  v: IntObject

template sign*(self: PyIntObject): IntSign = self.v.sign

#proc compatSign(op: PyIntObject): SDigit{.inline.} = cast[SDigit](op.sign)
# NOTE: CPython uses 0,1,2 for IntSign, so its `_PyLong_CompactSign` is `1 - sign`

template newBodyUse(x, newInt){.dirty.} =
  result = newPyIntSimple()
  result.v = newInt(x)
template newBody(x){.dirty.} = newBodyUse(x, newInt)
template genNew(T){.dirty.} =
  proc newPyInt*(i: T): PyIntObject = newBody(i)
template genNewGeneric(TT){.dirty.} =
  proc newPyInt*[T: TT](i: T): PyIntObject = newBody(i)

#proc newPyInt(i: Digit): PyIntObject

proc newPyInt*(o: IntObject): PyIntObject =
  ## deep copy, returning a new object
  newBody(o)

proc newPyInt*(o: PyIntObject): PyIntObject{.inline.} =
  ## deep copy, returning a new object
  newPyInt(o.v)

genNew Digit
genNewGeneric SomeSignedInt
genNewGeneric SomeUnsignedInt and not Digit

proc newPyIntFromPtr*(p: pointer): PyIntObject =
  ## `PyLong_FromVoidPtr`
  newBodyUse(p, newIntFromPtr)

proc newPyIntFromPtr*[I: ref | ptr](i: I): PyIntObject =
  newPyIntFromPtr cast[pointer](i)

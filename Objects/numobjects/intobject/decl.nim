

# this is a **very slow** bigint lib.
# Why reinvent such a bad wheel?
# because we seriously need low level control on our modules
# todo: make it a decent bigint module
#
import ../../pyobject

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

type IntSign = enum
  Negative = -1
  Zero = 0
  Positive = 1

const
  PyLong_SHIFT = digitBits

# only export for ./intobject
export Digit, TwoDigits, SDigit, digitBits, truncate,
 IntSign, PyLong_SHIFT


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

const sMaxValue = SDigit(high(Digit)) + 1
func fill[I: SomeInteger](digits: var typeof(PyIntObject.digits), ui: I){.cdecl.} =
  var ui = ui
  while ui != 0:
    digits.add Digit(
      when sizeof(I) <= sizeof(SDigit): ui
      else: ui mod I(sMaxValue)
    )
    ui = ui shr digitBits

proc newPyInt*[I: SomeSignedInt](i: I): PyIntObject =
  result = newPyIntSimple()
  result.digits.fill abs(i)

  if i < 0:
    result.sign = Negative
  elif i == 0:
    result.sign = Zero
  else:
    result.sign = Positive

proc newPyInt*[I: SomeUnsignedInt and not Digit](i: I): PyIntObject =
  result = newPyIntSimple()
  if i == 0:
    result.sign = Zero
    return
  result.sign = Positive
  result.digits.fill i

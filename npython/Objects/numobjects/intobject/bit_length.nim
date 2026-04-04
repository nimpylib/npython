
import ./decl
import pkg/intobject/bit_length
proc digitCount*(v: PyIntObject): int{.inline.} = v.v.digitCount ## `_PyLong_DigitCount`
proc numbits*(v: PyIntObject): int64 =
  ## `_PyLong_NumBits`
  assert not v.isNil
  v.v.numbits

proc bit_length*(self: PyIntObject): PyIntObject =
  ## int_bit_length_impl
  newPyInt self.v.bit_length

proc bit_count*(self: PyIntObject): PyIntObject =
  newPyInt self.v.bitCount

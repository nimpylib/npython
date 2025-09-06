
import ./bit_length_util
import ./decl
proc digitCount*(v: PyIntObject): int{.inline.} = v.digits.len  ## `_PyLong_DigitCount`
proc numbits*(v: PyIntObject): int64 =
  ## `_PyLong_NumBits`
  assert not v.isNil
  let ndigits = v.digitCount
  #assert ndigits == 0 or 
  if ndigits > 0:
    let ndigits1 = int64 ndigits-1
    let msd = v.digits[ndigits1]
    result = ndigits1 * digitBits
    result += bit_length(msd)

proc bit_length*(self: PyIntObject): PyIntObject =
  ## int_bit_length_impl
  let nbits = self.numbits
  assert nbits >= 0
  return newPyInt nbits


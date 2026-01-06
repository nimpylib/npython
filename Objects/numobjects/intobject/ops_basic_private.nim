
import ../numobjects_comm
template demote*(x: TwoDigits): Digit =
  Digit(x shr digitBits)
proc inplaceAdd*(a: PyIntObject, b: Digit) =
  var carry = TwoDigits(b)
  for i in 0..<a.digits.len:
    if carry == 0:
      return
    carry += TwoDigits(a.digits[i])
    a.digits[i] = truncate(carry)
    carry = carry.demote
  if TwoDigits(0) < carry:
    a.digits.add truncate(carry)

template doMulImpl*(result, b; loopVar, loopIter, src, dst) =
  ## assuming all Positive
  var carry = TwoDigits(0)
  let tb = TwoDigits(b)
  for loopVar in loopIter:
    carry += TwoDigits(src) * tb
    dst = truncate(carry)
    carry = carry.demote
  if 0'u64 < carry:
    result.digits.add truncate(carry)
proc inplaceMul*(a: var PyIntObject, b: Digit|uint8) =
  # assuming all Natural
  a.doMulImpl(b, d, a.digits.mitems, d, d)

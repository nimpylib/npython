
import ./decl
proc vLShift*(z: var openArray[Digit], a: openArray[Digit], m: int, d: int): Digit =
  ## Shift digit vector `a[0:m]` left by `d` bits, with 0 <= d < digitBits.
  ## Put the result in `z[0:m]`, and return the `d` bits shifted out of the top.
  assert d >= 0 and d < digitBits
  var carry: Digit = 0
  for i in 0..<m:
    let shifted = (TwoDigits(a[i]) shl d) or TwoDigits(carry)
    z[i] = truncate(shifted)
    carry = truncate(shifted shr digitBits)
  return carry

proc vRShift*(z: var openArray[Digit], a: openArray[Digit], m: int, d: int): Digit =
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


import std/bitops
const BitPerByte = 8
proc bit_length*(self: SomeInteger): int =
  when defined(noUndefinedBitOpts):
    sizeof(x) * BitPerByte bitops.countLeadingZeroBits x
  else:
    1 + fastLog2(
      when self is SomeSignedInt: abs(self)
      else: self
    )


from std/unicode import Rune
when defined(js):
  template castChar*(i: SomeInteger): char = cast[char](i and 255)
  template castChar*(i: Rune): char = char cast[uint8](i)
else:
  template castChar*(i: SomeInteger|Rune): char = cast[char](i)

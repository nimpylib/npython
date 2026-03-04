
import ./decl
import pkg/intobject/signbit
template gen1(name){.dirty.} =
  template name*(self: PyIntObject): untyped =
    bind name
    name(self.v)
gen1 setSignNegative
gen1 negative
gen1 zero
gen1 positive
gen1 flipSign
# `_PyLong_FlipSign`

gen1 negate
# currently the same as `flipSign`_ as we didn't have small int

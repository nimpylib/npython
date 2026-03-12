
import ./decl
import pkg/intobject/signbit
template gen1Aux(name, withName){.dirty.} =
  template name*(self: PyIntObject): untyped =
    bind withName
    withName(self.v)
template gen1is(name){.dirty.} = gen1Aux(name, `is name`)
template gen1(name){.dirty.} = gen1Aux(name, name)
gen1 setSignNegative
gen1is negative
gen1is zero
gen1is positive
gen1 flipSign
# `_PyLong_FlipSign`

gen1 negate
# currently the same as `flipSign`_ as we didn't have small int

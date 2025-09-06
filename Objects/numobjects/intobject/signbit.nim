
import ./decl
proc negate*(self: PyIntObject){.inline.} =
  self.sign = Negative

proc negative*(intObj: PyIntObject): bool {. inline .} =
  intObj.sign == Negative

proc zero*(intObj: PyIntObject): bool {. inline .} =
  intObj.sign == Zero

proc positive*(intObj: PyIntObject): bool {. inline .} =
  intObj.sign == Positive

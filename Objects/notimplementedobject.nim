import ./pyobject
import ./stringobject

declarePyType NotImplemented(tpToken):
  discard

let pyNotImplemented* = newPyNotImplementedSimple()  ## singleton

proc isNotImplemented*(obj: PyObject): bool =
  obj.id == pyNotImplemented.id

proc dollar(self: PyNotImplementedObject): string = "NotImplemented"
method `$`*(self: PyNotImplementedObject): string =
  self.dollar

implNotImplementedMagic repr:
  newPyString self.dollar


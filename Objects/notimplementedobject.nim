import ./pyobject
import ./stringobject
import ./exceptions

declarePyType NotImplemented():
  discard

let pyNotImplemented* = newPyNotImplementedSimple()  ## singleton

proc isNotImplemented*(obj: PyObject): bool =
  obj.id == pyNotImplemented.id

proc dollar(self: PyNotImplementedObject): string = "NotImplemented"
method `$`*(self: PyNotImplementedObject): string =
  self.dollar

implNotImplementedMagic repr:
  newPyString self.dollar

implNotImplementedMagic New(tp: PyObject):
  return pyNotImplemented

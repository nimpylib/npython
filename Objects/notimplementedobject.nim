import ./pyobject
import ./stringobject
import ./exceptions
import ./bltcommon; export bltcommon

declarePyType NotImplemented():
  discard

let pyNotImplemented* = newPyNotImplementedSimple()  ## singleton

proc isNotImplemented*(obj: PyObject): bool =
  obj.id == pyNotImplemented.id

proc dollar(self: PyNotImplementedObject): string = "NotImplemented"
method `$`*(self: PyNotImplementedObject): string =
  self.dollar

implNotImplementedMagic repr:
  newPyAscii self.dollar

implNotImplementedMagic New(_: PyObject):
  return pyNotImplemented

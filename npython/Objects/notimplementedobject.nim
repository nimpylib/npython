import ./pyobject
export pyNotImplemented

import ./bltcommon; export bltcommon
import ./exceptions
import ./stringobject

proc isNotImplemented*(obj: PyObject): bool =
  obj.id == pyNotImplemented.id

proc dollar(self: PyNotImplementedObject): string = "NotImplemented"
method `$`*(self: PyNotImplementedObject): string =
  self.dollar

methodMacroTmpl(NotImplemented)
implNotImplementedMagic repr:
  newPyAscii self.dollar

implNotImplementedMagic New(_: PyObject):
  return pyNotImplemented

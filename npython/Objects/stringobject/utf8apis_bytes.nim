
include ./common_h
import ../byteobjects
import ../../Utils/nexportc

proc asUTF8StringSafe*(self: PyStrObject): PyBytesObject =
  ## like `asUTF8String` but returns a new bytes object
  ##   with non-UTF8 characters replaced by `<REPLACEMENT>` instead of raising an exception.
  ##
  ## So no python exception will be raised.
  newPyBytes(self.asUTF8)

proc PyUnicode_AsUTF8StringSafe*(self: PyObject): PyBytesObject{.npyexportc.} =
  ## assuming `self` is a PyStrObject
  self.PyStrObject.asUTF8StringSafe


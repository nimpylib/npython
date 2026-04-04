
include ./common_h
from ../../Python/errors import PyErr_BadArgument

proc PyUnicode_fromStringAndSize*(u: string, size: int): PyObject =
  if size < 0: return newSystemError newPyAscii"Negative size passed to PyUnicode_FromStringAndSize"
  if size == 0: return newPyAscii()
  #TODO:PyUnicode_DecodeUTF8Stateful
  newPyStr u[0..<size]

proc PyUnicode_AsUTF8AndSize*(obj: PyObject, utf8: var string, size: var int): PyBaseErrorObject =
  if not obj.ofPyStrObject:
    size = -1
    return PyErr_BadArgument()
  (utf8, size) = obj.PyStrObject.asUTF8AndSize

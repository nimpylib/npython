
import std/strformat
import ./[pyobject, stringobject, exceptions]

import ./pyobject_apis/[
  attrs
]
export attrs

proc reprDefault*(self: PyObject): PyObject {. cdecl .} = 
  newPyString(fmt"<{self.typeName} object at {self.idStr}>")
proc PyObject_ReprNonNil*(obj: PyObject): PyObject =
  let fun = obj.getMagic(repr)
  if fun.isNil:
    return reprDefault obj
  result = fun(obj)
  result.errorIfNotString "__repr__"

template nullOr(obj; elseCall): PyObject =
  if obj.isNil: newPyAscii"<NULL>"
  else: elseCall obj

proc PyObject_Repr*(obj: PyObject): PyObject = obj.nullOr PyObject_ReprNonNil

proc PyObject_StrNonNil*(obj: PyObject): PyObject =
  let fun = obj.getMagic(str)
  if fun.isNil: return PyObject_ReprNonNil(obj)
  result = fun(obj)
  result.errorIfNotString "__str__"

proc PyObject_Str*(obj: PyObject): PyObject = obj.nullOr PyObject_StrNonNil

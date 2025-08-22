
import std/strformat
import ./[pyobject, exceptions, stringobject]

template asAttrNameOrRetE*(name: PyObject): PyStrObject =
  bind ofPyStrObject, typeName, newTypeError, newPyStr, PyStrObject
  bind formatValue, fmt
  if not ofPyStrObject(name):
    let n{.inject.} = typeName(name)
    return newTypeError newPyStr(
      fmt"attribute name must be string, not '{n:.200s}'",)
  PyStrObject name

proc PyObject_GetAttr*(v: PyObject, name: PyStrObject): PyObject =
  let fun = v.getMagic(getattr)
  assert not fun.isNil
  #XXX:type npython requires all pyType is `ready`
  # if fun.isNil: return newAttributeError(v, name)
  fun(v, name)
proc PyObject_GetAttr*(v: PyObject, name: PyObject): PyObject =
  PyObject_GetAttr(v, name.asAttrNameOrRetE)

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

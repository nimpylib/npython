
import std/strformat
import pkg/pyrepr
import ../[pyobject,
  stringobject, exceptions,
]

proc reprDefault*(self: PyObject): PyObject {. cdecl .} = 
  newPyString(fmt"<{self.typeName} object at {self.idStr}>")
proc PyObject_ReprNonNil*(obj: PyObject): PyObject =
  let fun = obj.getMagic(repr)
  if fun.isNil:
    return reprDefault obj
  result = fun(obj)
  retIfExc result
  result.errorIfNotString "__repr__"

template nullOr(obj; elseCall): PyObject =
  if obj.isNil: newPyAscii"<NULL>"
  else: elseCall obj

proc PyObject_Repr*(obj: PyObject): PyObject = obj.nullOr PyObject_ReprNonNil

proc PyObject_StrNonNil*(obj: PyObject): PyObject =
  let fun = obj.getMagic(str)
  if fun.isNil: return PyObject_ReprNonNil(obj)
  result = fun(obj)
  retIfExc result
  result.errorIfNotString "__str__"

proc PyObject_Str*(obj: PyObject): PyObject = obj.nullOr PyObject_StrNonNil

proc PyObject_ASCIINonNil*(us: PyObject): PyObject =
  let repr = PyObject_ReprNonNil us
  retIfExc repr
  # repr is guaranteed to be a PyUnicode object by PyObject_Repr
  let str = PyStrObject repr
  if str.isAscii:
    return str
  let s = pyasciiImpl $str
  newPyAscii s

proc PyObject_ASCII*(obj: PyObject): PyObject = obj.nullOr PyObject_ASCIINonNil

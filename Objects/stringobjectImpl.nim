
import std/strformat
import pyobject
import baseBundle
import stringobject

export stringobject


# redeclare this for these are "private" macros

methodMacroTmpl(Str)


implStrMagic eq:
  if not other.ofPyStrObject:
    return pyFalseObj
  if self.str == PyStrObject(other).str:
    return pyTrueObj
  else:
    return pyFalseObj


implStrMagic str:
  self

implStrMagic len:
  newPyInt self.len

implStrMagic repr:
  newPyString(repr self)


implStrMagic hash:
  newPyInt(self.hash)

# TODO: encoding, errors params
implStrMagic New(tp: PyObject, obj: PyObject):
  # ref: unicode_new -> unicode_new_impl -> PyObject_Str
  let fun = obj.getMagic(str)
  if fun.isNil:
    return obj.callMagic(repr)
  result = fun(obj)
  if not result.ofPyStrObject:
    return newTypeError newPyStr(
      &"__str__ returned non-string (type {result.pyType.name:.200s})")


implStrMagic add(i: PyStrObject):
  self & i

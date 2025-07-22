import strformat
import hashes
import macros

import pyobject
import exceptions
import stringobject
import boolobject
import numobjects
import ./noneobject

export boolobject

method `$`*(obj: PyBoolObject): string = 
  $obj.b

methodMacroTmpl(Bool)

implBoolMagic Not:
  newPyBool self != pyTrueObj

implBoolMagic bool:
  self


implBoolMagic And:
  let otherBoolObj = other.callMagic(bool)
  errorIfNotBool(otherBoolObj, "__bool__")
  newPyBool self.b and PyBoolObject(otherBoolObj).b

implBoolMagic Xor:
  let otherBoolObj = other.callMagic(bool)
  errorIfNotBool(otherBoolObj, "__bool__")
  newPyBool self.b xor PyBoolObject(otherBoolObj).b

implBoolMagic Or:
  let otherBoolObj = other.callMagic(bool)
  errorIfNotBool(otherBoolObj, "__bool__")
  newPyBool self.b or PyBoolObject(otherBoolObj).b

implBoolMagic eq:
  let otherBoolObj = other.callMagic(bool)
  errorIfNotBool(otherBoolObj, "__bool__")
  let otherBool = PyBoolObject(otherBoolObj).b
  newPyBool self.b == otherBool

implBoolMagic repr:
  if self.b:
    return newPyAscii("True")
  else:
    return newPyAscii("False")

implBoolMagic hash:
  newPyInt(Hash(self.b))


proc PyObject_IsTrue*(v: PyObject): bool =
  if v == pyTrueObj: return true
  if v == pyFalseObj: return false
  if v == pyNone: return false
  let boolMag = v.getMagic(bool)
  if not boolMag.isNil:
    return boolMag(v).PyBoolObject.b
  elif not v.getMagic(len).isNil:
    return v.getMagic(len)(v).PyIntObject.positive
  # We currently don't define:
  #   as_sequence
  #   as_mapping
  return true

implBoolMagic New(tp: PyObject, obj: PyObject):
  newPyBool PyObject_IsTrue obj


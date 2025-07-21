import strformat
import hashes
import macros

import pyobject
import exceptions
import stringobject
import boolobject
import numobjects

export boolobject

method `$`*(obj: PyBoolObject): string = 
  $obj.b

methodMacroTmpl(Bool)

implBoolMagic Not:
  if self == pyTrueObj:
    pyFalseObj
  else:
    pyTrueObj


implBoolMagic bool:
  self


implBoolMagic And:
  let otherBoolObj = other.callMagic(bool)
  errorIfNotBool(otherBoolObj, "__bool__")
  if self.b and PyBoolObject(otherBoolObj).b:
    return pyTrueObj
  else:
    return pyFalseObj

implBoolMagic Xor:
  let otherBoolObj = other.callMagic(bool)
  errorIfNotBool(otherBoolObj, "__bool__")
  if self.b xor PyBoolObject(otherBoolObj).b:
    return pyTrueObj
  else:
    return pyFalseObj

implBoolMagic Or:
  let otherBoolObj = other.callMagic(bool)
  errorIfNotBool(otherBoolObj, "__bool__")
  if self.b or PyBoolObject(otherBoolObj).b:
    return pyTrueObj
  else:
    return pyFalseObj

implBoolMagic eq:
  let otherBoolObj = other.callMagic(bool)
  errorIfNotBool(otherBoolObj, "__bool__")
  let otherBool = PyBoolObject(otherBoolObj).b
  if self.b == otherBool:
    return pyTrueObj
  else:
    return pyFalseObj

implBoolMagic repr:
  if self.b:
    return newPyAscii("True")
  else:
    return newPyAscii("False")

implBoolMagic hash:
  newPyInt(Hash(self.b))

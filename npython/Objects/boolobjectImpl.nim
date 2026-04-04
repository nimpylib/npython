import strformat
import hashes
import macros

import pyobject
import exceptions
import stringobject
import ./boolobject
export boolobject
import ./numobjects/intobject_decl
import ./noneobject
import ./bltcommon; export bltcommon


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


proc PyObject_IsTrue*(v: PyObject, res: var bool): PyBaseErrorObject =
  template ret(b: bool) =
    res = b
    return nil
  if v == pyTrueObj: ret true
  if v == pyFalseObj: ret false
  if v == pyNone: ret false
  let boolMag = v.getMagic(bool)
  if not boolMag.isNil:
    let obj = boolMag(v)
    errorIfNotBool obj, "__bool__"
    ret obj.PyBoolObject.b
  elif not v.getMagic(len).isNil:
    let obj = v.getMagic(len)(v)
    errorIfNot int, obj, "__bool__"
    ret obj.PyIntObject.positive
  # We currently don't define:
  #   as_sequence
  #   as_mapping
  ret true

implBoolMagic New(_: PyObject, obj):
  var b: bool
  retIfExc PyObject_IsTrue(obj, b)
  newPyBool b


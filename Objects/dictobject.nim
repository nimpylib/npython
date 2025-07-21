import strformat

import strutils
import tables
import macros

import pyobject 
import listobject
import baseBundle
import ../Utils/utils

import ./hash
export hash

# currently not ordered
# nim ordered table has O(n) delete time
# todo: implement an ordered dict 
declarePyType dict(reprLock, mutable):
  table: Table[PyObject, PyObject]


proc newPyDict* : PyDictObject = 
  result = newPyDictSimple()
  result.table = initTable[PyObject, PyObject]()

proc hasKey*(dict: PyDictObject, key: PyObject): bool = 
  return dict.table.hasKey(key)

proc `[]`*(dict: PyDictObject, key: PyObject): PyObject = 
  return dict.table[key]


proc `[]=`*(dict: PyDictObject, key, value: PyObject) = 
  dict.table[key] = value


template checkHashableTmpl(obj) = 
  let hashFunc = obj.pyType.magicMethods.hash
  if hashFunc.isNil:
    let tpName = obj.pyType.name
    let msg = "unhashable type: " & tpName
    return newTypeError newPyStr(msg)


implDictMagic contains, [mutable: read]:
  checkHashableTmpl(other)
  try:
    result = self.table.getOrDefault(other, nil)
  except DictError:
    let msg = "__hash__ method doesn't return an integer or __eq__ method doesn't return a bool"
    return newTypeError newPyAscii(msg)
  if result.isNil:
    return pyFalseObj
  else:
    return pyTrueObj

implDictMagic repr, [mutable: read, reprLockWithMsg"{...}"]:
  var ss: seq[UnicodeVariant]
  for k, v in self.table.pairs:
    let kRepr = k.callMagic(repr)
    let vRepr = v.callMagic(repr)
    errorIfNotString(kRepr, "__str__")
    errorIfNotString(vRepr, "__str__")
    ss.add newUnicodeUnicodeVariant PyStrObject(kRepr).str.toRunes &
      toRunes": " &
      PyStrObject(vRepr).str.toRunes
  return newPyString(toRunes"{" & ss.joinAsRunes(", ") & toRunes"}")


implDictMagic len, [mutable: read]:
  newPyInt(self.table.len)

implDictMagic New:
  newPyDict()
  

implDictMagic getitem, [mutable: read]:
  checkHashableTmpl(other)
  try:
    result = self.table.getOrDefault(other, nil)
  except DictError:
    let msg = "__hash__ method doesn't return an integer or __eq__ method doesn't return a bool"
    return newTypeError newPyAscii(msg)
  if not (result.isNil):
    return result

  var msg: PyStrObject
  let repr = other.pyType.magicMethods.repr(other)
  if repr.isThrownException:
    msg = newPyAscii"exception occured when generating key error msg calling repr"
  else:
    msg = PyStrObject(repr)
  return newKeyError(msg)


implDictMagic setitem, [mutable: write]:
  checkHashableTmpl(arg1)
  try:
    self.table[arg1] = arg2
  except DictError:
    let msg = "__hash__ method doesn't return an integer or __eq__ method doesn't return a bool"
    return newTypeError newPyAscii(msg)
  pyNone

implDictMethod copy(), [mutable: read]:
  let newT = newPyDict()
  newT.table = self.table
  newT

# in real python this would return a iterator
# this function is used internally
proc keys*(d: PyDictObject): PyListObject = 
  result = newPyList()
  for key in d.table.keys:
    let rebObj = tpMethod(List, append)(result, @[key])
    if rebObj.isThrownException:
      unreachable("No chance for append to thrown exception")


proc update*(d1, d2: PyDictObject) = 
  for k, v in d2.table.pairs:
    d1[k] = v

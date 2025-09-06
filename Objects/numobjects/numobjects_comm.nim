
import ../../Include/internal/pycore_object
export Py_CheckSlotResult
import ./[
  intobject_decl, floatobject_decl,
]
import ../[
  pyobject, exceptions, stringobject, boolobject,
]
import std/strformat
export intobject_decl, floatobject_decl,
  pyobject, exceptions, boolobject, stringobject

let pyIntZero* = newPyInt(0)
let pyIntOne* = newPyInt(1)
let pyIntTen* = newPyInt(10)

let divZeroError = newPyAscii"division by zero"
template retZeroDiv* =
  return newZeroDivisionError divZeroError

proc newPyFloat*(pyInt: PyIntObject): PyFloatObject = 
  result = newPyFloat(pyInt.toFloat)

proc PyNumber_Index*(item: PyObject, res: var PyIntObject): PyBaseErrorObject =
  ## - returns nil if no error;
  ## - returns TypeError or other exceptions raised by `item.__index__`
  if item.ofPyIntObject:
    res = PyIntObject item
    return
  let fun = item.getMagic(index)
  if fun.isNil:
    return newTypeError newPyStr(
    fmt"'{item.typeName:.200s}' object cannot be interpreted as an integer"
    )

  let i = fun(item)
  if i.ofPyIntObject:
    res = PyIntObject i
  elif i.isThrownException:
    return PyBaseErrorObject i
  else:
    return newTypeError newPyStr(
    fmt"__index__ returned non-int (type {item.pyType.name:.200s})"
    )

proc PyNumber_Index*(item: PyObject): PyObject =
  ## returns `PyIntObject` or exception
  ## 
  ## CPython's defined at abstract.c
  var res: PyIntObject
  result = PyNumber_Index(item, res)
  if result.isNil:
    result = res

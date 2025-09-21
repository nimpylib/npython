
import ../../Include/internal/pycore_object
export Py_CheckSlotResult
import ./[
  intobject_decl, floatobject_decl,
]
import ../[
  pyobject, exceptions, stringobject, boolobject, notimplementedobject,
]

import ../abstract/helpers
export null_error

export intobject_decl, floatobject_decl,
  pyobject, exceptions, boolobject, stringobject, notimplementedobject

let pyIntZero* = newPyInt(0)
let pyIntOne* = newPyInt(1)
let pyIntTen* = newPyInt(10)

let divZeroError = newPyAscii"division by zero"
template retZeroDiv* =
  return newZeroDivisionError divZeroError

proc newPyFloat*(pyInt: PyIntObject): PyFloatObject = 
  result = newPyFloat(pyInt.toFloat)

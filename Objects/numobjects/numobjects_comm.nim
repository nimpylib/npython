
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


when defined(wasm):
  template genIntConst(name; value: int){.dirty.} =
    template name*: PyIntObject = newPyInt(value)
else:
  template genIntConst(name; value: int) =
    let name*: PyIntObject = newPyInt(value)

genIntConst pyIntZero, 0
genIntConst pyIntOne, 1
genIntConst pyIntTwo, 2
genIntConst pyIntTen, 10

let divZeroError = newPyAscii"division by zero"
template retZeroDiv* =
  return newZeroDivisionError divZeroError

proc newPyFloat*(pyInt: PyIntObject): PyFloatObject = 
  result = newPyFloat(pyInt.toFloat)

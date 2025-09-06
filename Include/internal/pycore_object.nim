
import std/strformat
import ../../Objects/[
  pyobjectBase,
]
import ../cpython/pyerrors
import ../../Objects/exceptions

using obj: PyObject
using slot_name: cstring
proc failButNoExc(obj; slot_name): bool =
  Py_FatalError fmt"Slot {slot_name} of type {obj.typeName} failed " &
                        "without setting an exception"

proc succButExc(obj; slot_name): bool =
      Py_FatalError fmt"Slot {slot_name} of type {obj.typeName} succeeded " &
                        "with an exception set"

proc Py_CheckSlotResult*(obj; slot_name; success: bool, res: PyObject): bool{.pyCFuncPragma.} =
  ## `_Py_CheckSlotResult`
  ##
  ## .. hint:: CPython Py_FatalError if
  ##  `(res.isNil and not PyErr_Occurred) or (not res.isNil and PyErr_Occurred)`
  ##   but in NPython we use `res` to store exception when PyErr_Occurred, so
  ##   this function simply (and only can) fatal if res.isNil
  if not success:
    if res.isNil or
        not res.isThrownException:
          return failButNoExc(obj, slot_name)
  else:
    if not res.isNil and
        res.isThrownException:
          return succButExc(obj, slot_name)
  true

proc Py_CheckSlotResult*(obj; slot_name; res: PyObject): bool{.pyCFuncPragma.} =
  ## equal to things like
  ##
  ## assert Py_CheckSlotResult(obj, "__getitem__", result)
  if res.isNil: return failButNoExc(obj, slot_name)
  else:
    if res.isThrownException.unlikely:
      return succButExc(obj, slot_name)
  true
  #Py_CheckSlotResult(obj, slot_name, not res.isNil, res)
  

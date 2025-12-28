

import ../[pyobject, stringobject, noneobject]
include ./common_h
import ./utils

import ../exceptionsImpl
import ../stringobject/strformat
import ../../Python/call

proc PyErr_CreateException*(exception_type: PyTypeObject, value: PyObject): PyBaseExceptionObject =
  ## inner. unstable. `_PyErr_CreateException`
  let res = if value.isNil or value.isPyNone:
    call(exception_type)
  elif ofPyTupleObject(value):
    fastCall(exception_type, PyTupleObject(value).items)
  else:
    call(exception_type, value)
  result = PyBaseExceptionObject res
  if not result.isNil and not result.ofPyExceptionInstance:
    return newTypeError PyStrFmt&"""
calling {PyObject(exception_type):R} should have returned an instance of BaseException, not {result.typeName:s}"""

#[
proc setObject*(exc_type: PyTypeObject, value: PyObject) =
  ## `PyErr_SetObject`
  var is_subclass = false
  if not value.isNil and value.ofPyExceptionInstance:
    #TODO:subclass
    unreachable "subclass check not implemented"
  if not is_subclass:
    # We must normalize the value right now
    # Issue #23571: functions must not be called with an
    #        exception set
    let fixed_value = PyErr_CreateException(exc_type, value)
    if fixed_value.isNil:
  #ofPyBaseExceptionObject(exc_type)

proc setObject*(exc_type: PyObject, value: PyObject): PyObject =
  ## `PyErr_SetObject`
  if not exc_type.isNil and not exc_type.ofPyExceptionClass:
    return newSystemError PyStrFmt&"_PyErr_SetObject: exception {exc_type:R} is not a BaseException subclass"
  setObject(PyTypeObject(exc_type), value)
]#

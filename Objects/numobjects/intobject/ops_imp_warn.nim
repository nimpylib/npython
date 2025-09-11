
import ./ops
export ops
import ../numobjects_comm_with_warn
export PyNumber_Index, privatePyNumber_Index
import ./[
  signbit,
]
import ../../stringobject/strformat
template PyNumber_AsSsize_tImpl(pyObj: PyObject, res: var int, handleTypeErr, handleValAndOverfMsg){.dirty.} =
  let value = PyNumber_Index(pyObj)
  if not value.ofPyIntObject:
    res = -1
    handleTypeErr PyTypeErrorObject value
  else:
    let ivalue = PyIntObject value
    if not toInt(ivalue, res):
      handleValAndOverfMsg ivalue, (
        let tName{.inject.} = pyObj.pyType.name;
        newPyStr fmt"cannot fit '{tName:.200s}' into an index-sized integer")

proc PyNumber_AsSsize_t*(pyObj: PyObject, res: var int): PyExceptionObject =
  ## returns nil if no error; otherwise returns TypeError or OverflowError
  template handleTypeErr(e: PyTypeErrorObject) = return e
  template handleOverfMsg(_; msg: PyStrObject) = return newOverflowError msg
  PyNumber_AsSsize_tImpl pyObj, res, handleTypeErr, handleOverfMsg

proc PyNumber_AsSsize_t*(pyObj: PyObject, res: var PyExceptionObject): int =
  ## `res` [inout]
  ##
  ## CPython's defined at abstract.c
  template handleTypeErr(e: PyTypeErrorObject) = res = e
  template handleOverfMsg(_; msg: PyStrObject) =
    PyErr_Format res, msg
  res = nil
  PyNumber_AsSsize_tImpl(pyObj, result, handleTypeErr, handleOverfMsg)

proc PyNumber_AsClampedSsize_t*(pyObj: PyObject, res: var int): PyTypeErrorObject =
  ## C: `PyNumber_AsSsize_t(pyObj, NULL)`
  ## clamp result if overflow
  ## 
  ## returns nil unless Py's TypeError
  template handleTypeErr(e: PyTypeErrorObject) = return e
  template handleExc(i: PyIntObject; _) =
    res =
      if i.positive: high int
      else: low int
    return
  PyNumber_AsSsize_tImpl(pyObj, res, handleTypeErr, handleExc)

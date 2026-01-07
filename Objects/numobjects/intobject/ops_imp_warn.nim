
import ./[ops, ops_bitwise]
export ops, ops_bitwise
import ../numobjects_comm_with_warn
export PyNumber_Index, privatePyNumber_Index
import ./[
  signbit,
]
import ../../stringobject/strformat
import ../../exceptions/extra_utils
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

proc PyNumber_AsSsize_t*(pyObj: PyObject, excType: PyTypeObject; resExc: var PyBaseErrorObject): int =
  ## `excType` may be nil, in which case overflow clamps to low/high int
  ##   otherwise it must be an exception type
  ## 
  ## `resExc` [out]
  ##
  ## CPython's defined at abstract.c
  template handleTypeErr(e: PyTypeErrorObject) =
    resExc = e
    return
  template handleOverfMsg(_; msg: PyStrObject) =
    if excType.isNil:
      if PyIntObject(value).negative:
        result = low int
      else:
        result = high int
      return
    let t = PyErr_CreateException(excType, msg) #excType.getMagic(New)([PyObject msg], nil)
    if t.isThrownException:
      #TODO:get_normalization_failure_note
      discard
    resExc = PyBaseErrorObject t
    resExc.thrown = true
    return -1
  PyNumber_AsSsize_tImpl(pyObj, result, handleTypeErr, handleOverfMsg)
  resExc = nil

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

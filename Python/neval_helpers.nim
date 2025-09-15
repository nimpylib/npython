
import ./pythonrun/pyerr
import ../Objects/exceptions

template orPrintTb*(retRes: PyBaseErrorObject): bool{.dirty.} =
  bind PyErr_Print, PyExceptionObject
  if retRes.isNil: true
  else:
    PyErr_Print PyExceptionObject(retRes)
    false

template orPrintTb*(retRes): bool{.dirty.} =
  bind PyErr_Print, PyExceptionObject
  if retRes.isThrownException:
    PyErr_Print PyExceptionObject(retRes)
    false
  else:
    true


import ./[
  traceback,
]
import ../Objects/exceptions

template orPrintTb*(retRes: PyBaseErrorObject): bool{.dirty.} =
  bind printTb, PyExceptionObject
  if retRes.isNil: true
  else:
    printTb PyExceptionObject(retRes)
    false

template orPrintTb*(retRes): bool{.dirty.} =
  bind printTb, PyExceptionObject
  if retRes.isThrownException:
    printTb PyExceptionObject(retRes)
    false
  else:
    true


import ../[stringobject, tupleobjectImpl]
import ../exceptions
include ./common_h
proc setString*(e: PyBaseExceptionObject, m: PyStrObject) =
  withSetItem e.args, acc: acc[0] = m
proc setString*(e: PyBaseExceptionObject, m: string) =
  ## `_PyErr_SetString`, 
  e.setString newPyStr m

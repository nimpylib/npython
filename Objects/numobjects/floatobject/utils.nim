
import ../numobjects_comm
proc Py_convert_int_to_double*(v: var PyObject, dbl: var float): bool =
  # `_Py_convert_int_to_double`

  if v.ofPyIntObject:
    var exc: PyOverflowErrorObject
    dbl = toFloat(PyIntObject v, exc)
    if not exc.isNil:
      v = exc
      return
  else:
    v = pyNotImplemented
    return
  true

template CONVERT_TO_DOUBLE*(obj, dbl) =
  if obj.ofPyFloatObject:
    dbl = PyFloatObject(obj).asDouble
  elif not Py_convert_int_to_double(obj, dbl):
    return obj

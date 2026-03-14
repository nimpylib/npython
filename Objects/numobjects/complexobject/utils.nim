
import ../../pyobject
import ../floatobject/[decl, utils]
import pkg/errno/[errnoUtils, errnoConsts]


proc real_to_double(pobj: var PyObject, dbl: var float): bool =
  if pobj.ofPyFloatObject:
    dbl = PyFloatObject(pobj).v
  elif not Py_convert_int_to_double(pobj, dbl): return false
  true

template COMPLEX_BINOPimpl*(methodName, op) =
  ## `COMPLEX_BINOP`
  bind isErr, EDOM, real_to_double
  var
    casted: PyComplexObject

  var a: PyComplex
  if other.ofPyComplexObject:
    casted = PyComplexObject(other)
    let b = casted.v
    var v = selfNoCast
    if selfNoCast.ofPyComplexObject:
      let s = PyComplexObject(selfNoCast)
      a = op(s.v, b)
    elif not real_to_double(v, a.real):
      return v
    else:
      a = op(a.real, b)
  elif not selfNoCast.ofPyComplexObject:
    return pyNotImplemented
  # elif other.ofPyIntObject:
  #   casted = newPyFloat(PyIntObject(other))
  else:
    var b: float
    var o = other
    if not real_to_double(o, b):
      return o
    a = op(PyComplexObject(selfNoCast).v, b)
  
  if isErr EDOM:
    return newZeroDivisionError newPyAscii"division by zero"
  result = newPyComplex a

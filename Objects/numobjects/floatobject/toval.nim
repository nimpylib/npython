
import ./decl
import ../numobjects_comm
import ../../[
  pyobjectBase,
  exceptions, 
]
template asDouble*(op: PyFloatObject): float = op.v
template asDouble*(op: PyFloatObject; v: var float): PyBaseErrorObject =
  ## `PyFloat_AS_DOUBLE`
  v = op.asDouble
  PyBaseErrorObject nil
proc PyFloat_AsDouble*(op: PyObject; v: var float): PyBaseErrorObject =
  if op.ofPyFloatObject:
    return op.PyFloatObject.asDouble v
  var fun = op.pyType.magicMethods.float
  if fun.isNil:
    var res: PyIntObject
    let exc = PyNumber_Index(op, res)
    if exc.isNil:
      retIfExc res.toFloat v
  else:
    let res = fun(op)
    errorIfNot Float, "float", res, (op.typeName & ".__float__")
    return res.PyFloatObject.asDouble v

proc PyFloat_AsFloat*(op: PyObject; v: var float32): PyBaseErrorObject =
  ## EXT.
  var df: float
  result = PyFloat_AsDouble(op, df)
  if result.isNil:
    v = float32 df


import ./sysmodule/attrs
import ./call
import ../Objects/[
  pyobject, exceptions,
]
import ../Include/internal/pycore_global_strings

# ******* Unary functions *******
proc print_expr*(value: PyObject; res: var PyObject): PyBaseErrorObject =
  var hook: PyObject
  retIfExc PySys_GetAttr(pyID(displayhook), hook)
  res = call(hook, value)
  retIfExc res
  res = nil

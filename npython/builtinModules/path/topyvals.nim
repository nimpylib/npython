
import ../private/[utils,]
import pkg/pystrbytes_decl

impObjects [
  pyobject,
  exceptions,
  stringobject,
  tupleobjectImpl,
]
imp Python, getargs/tovals

proc toPy*(x: (PyStr, PyStr), res: var PyObject): PyBaseErrorObject =
  res = PyTuple_Pack(newPyStr x[0], newPyStr x[1])


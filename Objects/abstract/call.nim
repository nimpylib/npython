
import ../[pyobjectBase, stringobject]

import ../../Python/call

proc callMethod*(self: PyObject, name: PyStrObject, arg: PyObject): PyObject =
  ## `PyObject_CallMethodOneArg`
  assert not arg.isNil
  vectorcallMethod(name, [self, arg])
  
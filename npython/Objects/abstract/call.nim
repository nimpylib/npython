
import ../[pyobjectBase, stringobject]

import ../../Python/call

proc callMethod*(self: PyObject, name: PyStrObject): PyObject =
  ## `PyObject_CallMethodNoArg`
  vectorcallMethod(name, [self])

proc callMethod*(self: PyObject, name: PyStrObject, arg: PyObject): PyObject =
  ## `PyObject_CallMethodOneArg`
  assert not arg.isNil
  vectorcallMethod(name, [self, arg])
  
proc callMethodArgs*(self: PyObject, name: PyStrObject, args: varargs[PyObject]): PyObject =
  ## `PyObject_CallMethodObjArgs`
  var s = newSeq[PyObject](args.len+1)
  s[0] = self
  for i in 1..args.len:
    s[i] = args[i-1]
  vectorcallMethod(name, s)


import std/strformat
import ../../Objects/[stringobject, exceptions]
import ../../Utils/getfuncname
import ./pyerrors_fatal

{.push noReturn.}
proc Py_FatalErrorFunc*(funcname: cstring, message: string) = fatal_error(true, funcname, message, -1)
proc Py_FatalErrorFunc*(funcname: string, message: string) = Py_FatalErrorFunc(funcname.cstring, message)
{.pop.}


template Py_FatalError*(message) =
  bind instantiationFuncname
  Py_FatalErrorFunc(instantiationFuncname(), message)

proc PyErr_BadInternalCall*(filename: string, lineno: int): PySystemErrorObject =
  return newSystemError newPyStr &"{filename}:{lineno}: bad argument to internal function"
template PyErr_BadInternalCall*: PyBaseErrorObject =
  let tup = instantiationInfo()
  PyErr_BadInternalCall(tup.filename, tup.line)


import ../../Utils/getfuncname
import ./pyerrors_fatal

{.push noReturn.}
proc Py_FatalErrorFunc*(funcname: cstring, message: string) = fatal_error(true, funcname, message, -1)
proc Py_FatalErrorFunc*(funcname: string, message: string) = Py_FatalErrorFunc(funcname.cstring, message)
{.pop.}


template Py_FatalError*(message) =
  bind instantiationFuncname
  Py_FatalErrorFunc(instantiationFuncname(), message)

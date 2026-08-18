import ./[common, request]
import ../../Python/sysmodule_instance
import ../../Objects/[pyobject, stringobject, dictobject, noneobject, exceptions]

proc initUrllibPackage*(module: PyObject): PyObject =
  let requestModule = PyInit_request()
  retIfExc requestModule
  PyurllibModuleObject(module).request = requestModule
  sys.modules[newPyStr urllibRequestModuleName] = requestModule
  pyNone

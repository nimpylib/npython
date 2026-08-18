import ./urllib/[common, init]
import ../Objects/[pyobject, moduleobjectImpl, exceptions]

const urllibModuleName* = "urllib"

proc PyInit_urllib*: PyObject =
  result = PyModule_CreateInitialized(urllib)
  retIfExc result
  retIfExc initUrllibPackage(result)

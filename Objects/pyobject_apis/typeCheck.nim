

import ../pyobject
proc ofPyCallable*(x: PyObject): bool =
  ## PyCallable_Check
  if x.isNil: return
  not x.getMagic(call).isNil



import ../Objects/[pyobject, baseBundle, methodobject, funcobjectImpl]

proc fastCall*(callable: PyObject, args: openArray[PyObject]): PyObject {. cdecl .} = 
  if callable.ofPyNimFuncObject:
    return tpMagic(NimFunc, call)(callable, @args)
  elif callable.ofPyFunctionObject:
    return tpMagic(Function, call)(callable, @args)
  else:
    let fun = getFun(callable, call)
    return fun(callable, @args)




import ../Objects/[pyobject, methodobject, funcobjectImpl,
  stringobject, exceptions,
  pyobject_apis,
]


proc fastCall*(callable: PyObject, args: openArray[PyObject]): PyObject {. cdecl .} = 
  if callable.ofPyNimFuncObject:
    return tpMagic(NimFunc, call)(callable, @args)
  elif callable.ofPyFunctionObject:
    return tpMagic(Function, call)(callable, @args)
  else:
    let fun = getFun(callable, call)
    return fun(callable, @args)

proc vectorcallMethod*(name: PyStrObject, args: openArray[PyObject]
    #[, nargsf: NArgsFlag]#, kwnames: PyObject = nil): PyObject =
  ## `PyObject_VectorcallMethod`
  assert not name.isNil
  assert args.len >= 1
  # Use args[0] as "self" argument
  let self = args[0]
  let callable = PyObject_GetAttr(self, name)
  retIfExc callable
  fastCall(callable, args)



import ../Objects/[pyobject, methodobject, funcobject,
  stringobject, exceptions,
  pyobject_apis,
  dictobject,
]

using kwnames: PyDictObject

proc fastCall*(callable: PyObject, args: openArray[PyObject]; kwnames: PyDictObject = nil): PyObject {. cdecl .} = 
  if callable.ofPyNimFuncObject:
    return tpMagic(NimFunc, call)(callable, @args, kwnames)
  elif callable.ofPyFunctionObject:
    # XXX:rec-dep:
    #return tpMagic(PyFunction, call)(callable, @args, kwnames)
    return callable.getMagic(call)(callable, @args, kwnames)
  else:
    let fun = getFun(callable, call)
    return fun(callable, @args, kwnames)

proc vectorcallMethod*(name: PyStrObject, args: openArray[PyObject]
    #[, nargsf: NArgsFlag]#, kwnames: PyDictObject = nil): PyObject =
  ## `PyObject_VectorcallMethod`
  ## 
  ## .. note:: PY-DIFF this differs CPython's vectorcall as kwnames is not a tuple, but a dict
  assert not name.isNil
  assert args.len >= 1
  # Use args[0] as "self" argument
  let self = args[0]
  let callable = PyObject_GetAttr(self, name)
  retIfExc callable
  fastCall(callable, args, kwnames)

proc call*(fun: PyObject): PyObject =
  ## `_PyObject_CallNoArgs`
  fun.fastCall([])

proc call*(fun, arg: PyObject): PyObject =
  ## `_PyObject_CallOneArg`
  fun.fastCall([arg])

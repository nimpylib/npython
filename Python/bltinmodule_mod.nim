
import ./[
  bltinmodule,
  builtindict,
  coreconfig,
]

import ../Objects/[
  pyobject, exceptions,
  dictobject,
  moduleobjectImpl,
  stringobject,
]
import ../Objects/numobjects/intobject_decl

declarePyType BuiltinsModule(base(Module)):
  discard


proc PyBuiltin_Init*(config: PyConfig): PyObject =
  let moduObj = PyModule_CreateInitialized(builtins)
  retIfExc moduObj
  let modu = PyBuiltinsModuleObject moduObj
  let dict = PyEval_GetBuiltins()
  modu.dict = dict
  let debug = newPyInt int config.optimization_level == 0
  dict[newPyAscii"__debug__"] = debug
  modu



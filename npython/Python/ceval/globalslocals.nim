
import ../../Objects/[
  pyobjectBase,
  dictobjectImpl,
  exceptions,
  stringobject,
  noneobject,
  moduleobject,
  frameobject,
]
import ../pystate
import ../builtindict
import ../neval_frame
import ../../Objects/abstract/[mapping, dunder]
import ../../Include/internal/pycore_global_strings

using globals: PyObject
proc get_globals_builtins(globals; builtins: var PyObject): PyBaseErrorObject =
  if globals.ofPyDictObject:
    let d = PyDictObject globals
    discard d.getItemRef(pyDUId(builtins), builtins)
  else:
    retIfExc PyMapping_GetOptionalItem(
                    globals, pyDUId(builtins), builtins)

proc set_globals_builtins(globals; builtins: PyObject): PyBaseErrorObject =
  if globals.ofPyDictObject:
    let d = PyDictObject globals
    retIfExc d.setItem(pyDUId(builtins), builtins)
  else:
    retIfExc PyObject_SetItem(
                    globals, pyDUId(builtins), builtins)

proc PyEval_EnsureBuiltins*(globals: PyObject): PyBaseErrorObject =
  var builtins: PyObject
  retIfExc get_globals_builtins(globals, builtins)
  if builtins.isNil:
    builtins = PyEval_GetBuiltins()
    retIfExc builtins
    retIfExc set_globals_builtins(globals, builtins)



proc PyEval_GetGlobalsFromRunningMain*(): PyObject =
  ## `_PyEval_GetGlobalsFromRunningMain`
  ##   Return the globals dictionary from the `__main__` module
  let mainMod = Py_GetMainModule()
  retIfExc mainMod
  if mainMod.isPyNone:
    return nil

  retIfExc Py_CheckMainModule(mainMod)
  PyModuleObject(mainMod).dict

proc PyEval_GetFrameLocals*(): PyObject =
  ## `PyEval_GetFrameLocals` / `_PyEval_GetFrameLocals`
  ##   Return the locals dictionary from the current frame
  let frame = PyEval_GetFrame()
  if frame.isNil:
    return newSystemError newPyAscii "frame does not exist"
  
  let locals = frame.getLocalsImpl
  retIfExc locals

  if locals.ofPyFrameLocalsProxyObject:
    let ret = newPyDict()
    retIfExc ret.updateImpl locals
    return ret

  assert locals.ofPyMapping
  return locals

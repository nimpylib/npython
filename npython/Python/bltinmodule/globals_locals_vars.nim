
import ../../Objects/[
  noneobject,
  dictobject,
  tupleobjectImpl,
  exceptions,
]
import ../../Include/internal/pycore_global_strings
import ../../Objects/pyobject_apis/attrs
import ../pythonrun/compile
import ../getargs/[
  dispatch,
]
import ../[
  neval_frame, neval,
]
import ../ceval/[globalslocals, ]

template getGlobalsOrLocals(inFrameGetter; elseRet: PyObject = pyNone) {.dirty.} =
  if not PyEval_GetFrame().isNil:
    result = inFrameGetter()
    assert not result.isNil
  else:
    result = PyEval_GetGlobalsFromRunningMain()
    if result.isNil:
      return elseRet

proc globals*(): PyObject{.bltin_clinicGen.} =
  getGlobalsOrLocals PyEval_GetGlobals

proc locals*(): PyObject{.bltin_clinicGen.} =
  getGlobalsOrLocals PyEval_GetFrameLocals

proc vars*(v: PyObject = nil): PyObject{.bltin_clinicGen.} =
  if v.isNil:
    getGlobalsOrLocals PyEval_GetFrameLocals, PyEval_GetFrameLocals()
  else:
    if PyObject_GetOptionalAttr(v, pyDUId(dict), result) == Missing:
      return newTypeError newPyAscii"vars() argument must have __dict__ attribute"

template reg(f) =
  registerBltinFunction astToStr(f), `builtin f`
template register_globals_locals_vars* =
  reg globals
  reg locals
  reg vars

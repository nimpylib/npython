
import ./pyerr
import ../neval
import ../../Include/internal/pycore_global_strings
import ../../Objects/[pyobjectBase,
  noneobject, codeobject,
  stringobjectImpl, exceptions,
  pyobject_apis/strings,
]

import ../sysmodule/[attrs, audit]


using filename: PyStrObject
using
  globals: PyDictObject
  locals: PyObject
#[
import ./builtindict
proc run_eval_code_obj_for_pyc(co: PyCodeObject, globals; locals): PyObject =
  let blt = newPyAscii "__builtins__"
  if not globals.contains blt:
    globals[blt] = PyEval_GetBuiltins()
  run_eval_code_obj(co, globals, locals)
]#
proc run_eval_code_obj(co: PyCodeObject, globals; locals): PyObject{.inline.} = evalCode(co, globals, locals)

proc run_eval_code_with_audit*(co: PyCodeObject, globals; locals): PyObject =
  retIfExc audit("exec", co)
  run_eval_code_obj(co, globals, locals)

template priRetIfExc*(exc: PyBaseErrorObject; excRes: untyped = true) =
  if not exc.isNil:
    PyErr_Print(exc)
    return excRes
template priRetIfExc*(res: PyObject; excRes: untyped = true) =
  if res.isThrownException:
    PyErr_Print(PyBaseErrorObject res)
    return excRes

proc PyRun_InteractiveLoopPre*: bool{.discardable.} =
  # when set ps1 & ps2, err is ignored in CPython
  var v: PyObject
  template setSysIfNon(attr; str) =
    var exists: bool
    priRetIfExc(PySys_GetOptionalAttr(pyId attr, v, exists), true)
    if v.isNil: priRetIfExc(PySys_SetAttrNonNil(pyId attr, newPyAscii str), true)
  setSysIfNon ps1, ">>> "
  setSysIfNon ps2, "... "
  false

proc getSysPsEnc*(): tuple[ps1, ps2, encoding: string] =
  ## encoding is sys.stdin.encoding
  var encoding = ""
  var attr: PyObject
  var exc: PyBaseErrorObject
  var exists: bool
  # if exc.isThrownException: discard
  var ps1, ps2: string
  template getSysTo(obj; itBeforeAsUtf8){.dirty.} =
    block it_blk:
      var it: PyObject
      exc = PySys_GetOptionalAttr(pyId obj, it, exists)
      if not it.isNil and it.ofPyStrObject:
        itBeforeAsUtf8
        obj = PyStrObject(it).asUTF8
  exc = PySys_GetOptionalAttr(pyId stdin, attr, exists)
  if not attr.isNil and not attr.isPyNone:
    getSysTo encoding: discard
  template str_it =
    it = PyObject_StrNonNil it
    if it.isThrownException:
      break it_blk
  getSysTo ps1, str_it
  getSysTo ps2, str_it
  (ps1, ps2, encoding)

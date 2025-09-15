
import ../../Objects/[
  pyobject,
  noneobject, exceptions,
  stringobject,
]
from ../errors import PyErr_FormatUnraisable
import ../[
  traceback, call,
]
import ../../Include/internal/pycore_global_strings
import ../pylifecycle/exit
import ../sysmodule/[attrs, audit, io]
import ./[
  pyerr_display, pyerr_sysexit_keyinter,
]
import ../../Utils/fileio

using exc: PyBaseErrorObject
proc handle_system_exit(exc) =
  var exitcode: int
  if Py_HandleSystemExitAndKeyboardInterrupt(exc, exitcode):
    Py_Exit(exitcode)

proc PyErr_PrintEx*(exc; set_sys_last_vars: bool=false){.pyCFuncPragma.} =
  template ss(id, val) =
    discard PySys_SetAttrNonNil(pyId id, val)
  let
    typ = exc.pyType
    tb = if exc.traceBacks.len > 0: newPyTraceback exc.traceBacks[^1] else: pyNone
  if set_sys_last_vars:
    ss last_exc, exc
    # Legacy version:
    ss last_type, typ
    ss last_value, exc
    ss last_traceback, tb
  var hook: PyObject
  var exists: bool
  discard PySys_GetOptionalAttr(pyId excepthook, hook, exists)
  let e = audit("sys.excepthook", if hook.isNil: pyNone else: hook, typ, exc, tb)
  if not e.isNil:
    if e.ofPyRuntimeErrorObject:
      #goto_done
      return
    PyErr_FormatUnraisable newPyAscii"Exception ignored in audit hook"
  if not hook.isNil:
    let res = fastCall(hook, [typ, exc, tb])
    if res.isThrownException:
      let exc2 = PyBaseErrorObject res
      handle_system_exit(exc2)
      stdout.flushFile
      PySys_EchoStderr "Error in sys.excepthook:"
      PyErr_DisplayException(exc2)
      PySys_EchoStderr "\nOriginal exception was:"
      PyErr_DisplayException(exc)
  else:
    assert not exists
    PySys_EchoStderr"sys.excepthook is missing"
    PyErr_DisplayException(exc)

template PyErr_Print*(exc: PyBaseErrorObject) =
  bind PyErr_PrintEx
  PyErr_PrintEx(exc, true)

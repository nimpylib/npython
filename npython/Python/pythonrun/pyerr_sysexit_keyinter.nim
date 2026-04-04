

import ../../Objects/pyobject_apis/[
  attrs, io,
]
import ../../Objects/[
  pyobject,
  noneobject, exceptions,
]
import ../sysmodule/[attrs, ]
import ../pylifecycle/pyruntime_singleton
import ../../Objects/numobjects/intobject
from ../coreconfig import Py_GetConfig
import ../../Include/internal/pycore_global_strings
import ../../Include/cpython/pyatomic
when not declared(stdout):
  import ../../Utils/fileio
import ../../Utils/utils


proc parse_exit_code(code: PyObject, exitcode_p: var int): bool =
  if code.ofPyIntObject:
    # gh-125842: Use a long long to avoid an overflow error when `long`
    # is 32-bit. We still truncate the result to an int.
    var ovf: bool
    let exitcode = PyIntObject(code).asLongAndOverflow(ovf)
    if ovf:
      # On overflow or other error, clear the exception and use -1
      # as the exit code to match historical Python behavior.
      #PyErr_Clear();
      exitcode_p = -1
      return true
    exitcode_p = exitcode
    return true
  elif code.isPyNone:
    exitcode_p = 0
    return true

proc Py_HandleSystemExitAndKeyboardInterrupt*(exc: PyBaseErrorObject, exitcode: var int): bool =
  #TODO:exit^C CtrlC ControlC
  if exc.ofPyKeyboardInterruptObject:
    Py_atomic_store addr PyRuntime.signals.unhandled_keyboard_interrupt, 1
    return
  if Py_GetConfig().inspect:
    return
  if not exc.ofPySystemExitObject:
    #[Don't exit if -i flag was given. This flag is set to 0
      when entering interactive mode for inspecting.]#
    return

  stdout.flushFile()

  let code = PyObject_GetAttr(exc, pyId code)
  var eo = PyObject exc
  if code.isThrownException:
    # If the exception has no 'code' attribute, print the exception below
    discard
  elif parse_exit_code(code, exitcode):
    return true
  else:
    # If code is not an int or None, print it below
    eo = code

  var sys_stderr: PyObject
  if not PySys_GetOptionalAttr(pyId stderr, sys_stderr).isNil:
    discard
  elif not sys_stderr.isNil and not sys_stderr.isPyNone:
    when declared(PyFile_WritelineObject):
      #TODO:fileio PyFile_WriteObject
      discard PyFile_WritelineObject(exc, sys_stderr)
    else:
      unreachable "not impl: PyFile_WriteObject" #TODO:sys.stderr
  else:
    let e: PyBaseErrorObject = PyObject_Println(exc, stderr, Py_PRINT_RAW)
    if not e.isNil:
      stderr.flushFile
  exitcode = 1
  return true

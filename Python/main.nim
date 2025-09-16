

import ./sysmodule/[
  audit, io,
]
import ../Objects/[
  stringobject,
  exceptions
]
import ../Objects/stringobject/strformat
import ./pythonrun
import ./coreconfig
import ../Utils/[fileio, compat,]


using exc: PyBaseErrorObject
proc err_print(exc; exitcode_p: var int): bool =
  ## pymain_err_print
  ## Display the current Python exception and return an exitcode
  var exitcode: int
  if Py_HandleSystemExitAndKeyboardInterrupt(exc, exitcode):
      exitcode_p = exitcode
      return true
  PyErr_Print(exc)


proc exit_err_print(exc): int =
  ## pymain_exit_err_print
  var exitcode = 1
  discard exc.err_print(exitcode)
  return exitcode


proc run_file_obj(program_name, filename: PyStrObject): int{.mayAsync.} =
  ## pymain_run_file_obj
  var exc: PyBaseErrorObject
  exc = audit("npython.run_file", filename)
  if not exc.isNil:
    return mayNewPromise exc.exit_err_print()
  let fp = try: fileio.open($filename, fmRead)  #TODO:Py_fopen
  except IOError:
    # // Ignore the OSError
    var errnoStr = ""
    #PySys_FormatStderr:
    when not defined(js):
      var errno{.importc, header: "<errno.h>".}: cint
      proc strerror(e: cint): cstring{.importc, header: "<errno.h>".}
      errnoStr = $errno
      var msg = "[Errno " & $strerror(errno) & "] "
    else:
      var msg = getCurrentExceptionMsg()
    template ignore(_) = discard
    handleFormatExc ignore:
      PySys_EchoStderr &"{program_name:S}: can't open file {filename:R}: {errnoStr}{msg}"
    return mayNewPromise 2

  int mayWaitFor PyRun_AnyFileObject(fp, filename, closeit=true)


proc run_file*(config: PyConfig): int{.mayAsync.} =
  ## pymain_run_file
  ## 
  ## inner
  let
    filename = newPyStr config.run_filename
    program_name = newPyStr pyConfig.program_name

  run_file_obj(program_name, filename)

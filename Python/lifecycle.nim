import coreconfig
# init bltinmodule
import bltinmodule
import ../Objects/[
  pyobject, exceptions,
  dictobject,
  stringobject,
  listobject,
  typeobject,
  ]
import ../Utils/[utils, compat]
import ../Include/cpython/pyerrors
import ./[
  neval_helpers,
  sysmodule_instance,
  sysmodule,
]

import std/os except getCurrentDir

when declared(system.outOfMemHook):
  # if not JS
  proc outOfMemHandler =
    let e = new OutOfMemDefect
    raise e
  system.outOfMemHook = outOfMemHandler

when not defined(js):
  proc controlCHandler {. noconv .} =
    raise newException(InterruptError, "")

  system.setControlCHook(controlCHandler)

template chk(e: PyBaseErrorObject, msg: string) =
  let ret = e
  if not ret.orPrintTb:
    Py_FatalError msg

proc pyInit*(args: seq[string]) =

  # pycore_init_types
  for t in bltinTypes:
    t.typeReady

  chk PySys_Create(sys): "failed to create sys module"

  sys.modules[sys.name] = sys

  pyConfig.executable = getAppFilenameCompat()
  pyConfig.argv = args
  #TODO:argv shall be filtered to remove `-X`,etc
  pyConfig.orig_argv = @[pyConfig.executable] & args

  chk PySys_UpdateConfig(sys, pyConfig): "failed to update sys from config"

  if args.len == 0:
    sys.path.add newPyAscii()
  else:
    pyConfig.filepath = joinPath(getCurrentDir(), args[0])
    pyConfig.filename = pyConfig.filepath.extractFilename()
    let s = newPyStr pyConfig.filepath.parentDir()
    when s is_not PyStrObject:
      if s.isThrownException: Py_FatalError(
        "failed to add parent dir " & pyConfig.filepath & " to sys.path"
      )
    sys.path.add s
  when defined(debug):
    echo "sys.path: " & $sys.path

  

import coreconfig
# init bltinmodule
import bltinmodule
import ../Objects/[
  pyobject, exceptions,
  dictobject,
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


proc pyInit*(args: seq[string]) =

  # # pycore_init_types
  for t in bltinTypes:
    t.typeReady

  let ret = PySys_Create sys
  if not ret.orPrintTb:
    Py_FatalError("failed to create sys module")
  sys.modules[sys.name] = sys

  if args.len == 0:
    pyConfig.path = getCurrentDir()
  else:
    pyConfig.filepath = joinPath(getCurrentDir(), args[0])
    pyConfig.filename = pyConfig.filepath.extractFilename()
    pyConfig.path = pyConfig.filepath.parentDir()
  when defined(debug):
    echo "Python path: " & pyConfig.path

  

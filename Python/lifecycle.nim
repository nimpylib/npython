import coreconfig
# init bltinmodule
import bltinmodule
import ../Objects/[pyobject, typeobject]
import ../Utils/utils

import std/os


proc outOfMemHandler =
  let e = new OutOfMemDefect
  raise e

when declared(system.outOfMemHook):
  # if not JS
  system.outOfMemHook = outOfMemHandler

when not defined(js):
  proc controlCHandler {. noconv .} =
    raise newException(InterruptError, "")

  system.setControlCHook(controlCHandler)

proc pyInit*(args: seq[string]) = 
  for t in bltinTypes:
    t.typeReady

  if args.len == 0:
    pyConfig.path = os.getCurrentDir()
  else:
    pyConfig.filepath = joinPath(os.getCurrentDir(), args[0])
    pyConfig.filename = pyConfig.filepath.extractFilename()
    pyConfig.path = pyConfig.filepath.parentDir()
  when defined(debug):
    echo "Python path: " & pyConfig.path

  

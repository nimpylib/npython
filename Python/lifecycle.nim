import coreconfig
import ../Objects/[
  pyobject, exceptions,
  stringobject,
  listobject,
  typeobject,
  ]
import ../Utils/[utils, compat, trans_imp]
import ../Include/cpython/pyerrors
import ./[
  neval_helpers,
  sysmodule_instance,
  sysmodule,
]
impExp pylifecycle,
  builtins

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

  chk PySys_Create(sys): "can't initialize sys module"

  chk pycore_init_builtins(): "can't initialize builtins module"

  #_PyPathConfig_UpdateGlobal
  # COPY2(program_full_path, executable)

  #
  #[initconfig.c:config_parse_cmdline
  const wchar_t* program = config->program_name;
  if (!program && argv->length >= 1) {
      program = argv->items[0];
  }
  ]#
  pyConfig.program_name = getAppFilenameCompat()
  pyConfig.executable = pyConfig.program_name
  when compiles(expandFilename""):
    pyConfig.executable = pyConfig.executable.expandFilename()
  pyConfig.argv = args
  #TODO:argv shall be filtered to remove `-X`,etc
  pyConfig.orig_argv = @[pyConfig.executable] & args

  chk PySys_UpdateConfig(sys, pyConfig): "failed to update sys from config"

  if args.len == 0:
    sys.path.add newPyAscii()
  else:
    let filepath = joinPath(getCurrentDir(), args[0])
    pyConfig.run_filename = filepath
    pyConfig.filename = filepath.extractFilename()
    let s = newPyStr filepath.parentDir()
    when s is_not PyStrObject:
      if s.isThrownException: Py_FatalError(
        "failed to add parent dir " & filepath & " to sys.path"
      )
    sys.path.add s
  when defined(debug):
    echo "sys.path: " & $sys.path

  

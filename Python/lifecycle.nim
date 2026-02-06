import coreconfig
import ../Objects/[
  pyobject, exceptionsImpl,
  stringobject,
  listobject,
  typeobject,
  ]
import ../Utils/[utils, nexportc, compat, trans_imp]
import ../Include/cpython/pyerrors
import ../Include/internal/pycore_int
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

template handle_PyStatus_ERR(m) = Py_FatalError m

template chk(e: PyBaseErrorObject, msg: string) =
  let ret = e
  if not ret.orPrintTb:
    handle_PyStatus_ERR msg


{.push inline.}
proc pycore_init_types =
  for t in bltinTypes:
    t.typeReady
  chk PyExc_InitTypes(): "failed to initialize an exception type"
  Py_Int_Float_InitTypes handle_PyStatus_ERR

const
  wasm = defined(wasm)
  needCallMain = defined(npy_noMain)
when needCallMain:
  when wasm:
    #XXX:NIM-BUG: bypass a new static INLINE was generated
    {.emit: """void NimMain();""".}
    proc NimMain() {.importc, nodecl.}
  else:
    proc NimMain() {.importc, cdecl.}
proc pycore_interp_init =
  when needCallMain:
    NimMain()
  pycore_init_types()

  chk PySys_Create(sys): "can't initialize sys module"

  chk pycore_init_builtins(): "can't initialize builtins module"

using config: PyConfig
proc pyinit_config(config) =
  pycore_interp_init()


proc interpreter_update_config() =
  PyInterpreterState_GET_long_state().max_str_digits = PY_INT_DEFAULT_MAX_STR_DIGITS # config->int_max_str_digits

proc init_interp_main() =
  interpreter_update_config()
proc pyinit_main() =
  init_interp_main()
{.pop.}

proc Py_InitializeFromConfig*(config) =
  pyinit_config(config)

  pyinit_main()


proc pyInit*(args: seq[string]) =

  Py_InitializeFromConfig(pyConfig)
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
  when not wasm and compiles(expandFilename""):
    pyConfig.executable = pyConfig.executable.expandFilename()
  pyConfig.argv = args
  #TODO:argv shall be filtered to remove `-X`,etc
  pyConfig.orig_argv = @[pyConfig.executable] & args

  chk PySys_UpdateConfig(sys, pyConfig): "failed to update sys from config"

  if args.len == 0:
    sys.path.add newPyAscii()
  else:
    let filepath = absolutePathCompat args[0]
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

proc Py_Initialize*(){.npyexportc.} = pyInit @[]


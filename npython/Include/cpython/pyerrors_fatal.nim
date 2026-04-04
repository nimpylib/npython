
import ../../Utils/[clib, compat]
import ../internal/defines
#[
import ../internal/defines/[
  pycore_runtime_structs, pycore_traceback,
]
import ./private/runtime_singleton
]#

const Js = defined(js)
when Js:
  template withPUTS(body){.dirty.} =
    var tempPUTS: string
    body
    errEchoCompatNoRaise tempPUTS
  template tPUTS(_; s: string) = tempPUTS.add s
else:
  import ../../Utils/fileio
  template withPUTS(body) =
    body
    stderr.write '\n'
  template tPUTS(_; s: string) =
    stderr.write s
template PUTS(_; s: string) =
  try: tPUTS(_, s)
  except IOError: discard
#[
proc dump_runtime(runtime: var PyRuntimeState) =
  withPUTS:
    PUTS(fd, "Python runtime state: ")
    let finalizing = runtime.getFinalizing()
    if not finalizing.isNil:
        PUTS(fd, "finalizing (tstate=0x")
        PUTS(fd, Py_DumpHexadecimal(cast[uint](finalizing), sizeof(finalizing) * 2))
        PUTS(fd, ")")
    elif runtime.initialized:
        PUTS(fd, "initialized")
    elif runtime.core_initialized:
        PUTS(fd, "core initialized")
    elif runtime.preinitialized:
        PUTS(fd, "preinitialized")
    elif runtime.preinitializing:
        PUTS(fd, "preinitializing")
    else:
        PUTS(fd, "unknown")
]#

proc fatal_error_exit(status: int){.noReturn, inline.} =
  if status < 0:
    when MS_WINDOWS and Py_DEBUG:
      DebugBreak()
    abort()
  else:
    quitCompat status

proc fatal_error*(header: static bool, prefix: cstring, msg: string, status: int){.noReturn, raises: [].} =
  ## XXX: CPython's arg0 is an fileno int, but all usages are using `fileno(stderr)`
  var reentrant{.global.} = false
  if reentrant:
    #[Py_FatalError() caused a second fatal error.
      Example: flush_std_files() raises a recursion error.]#
    fatal_error_exit(status)
  reentrant = true
  withPUTS:
    when header:
      PUTS f, "Fatal Python error: "
      if not prefix.isNil:
        PUTS f, $prefix
        PUTS f, ": "
      PUTS f, if msg == "": "<message not set>" else: msg
  
  #dump_runtime PyRuntime

  #[Check if the current thread has a Python thread state
       and holds the GIL.

       tss_tstate is NULL if Py_FatalError() is called from a C thread which
       has no Python thread state.

       tss_tstate != tstate if the current Python thread does not hold the GIL.]#
  
  #TODO:fatal_error

  #Py_DumpExtensionModules(interp)

  fatal_error_exit(status)


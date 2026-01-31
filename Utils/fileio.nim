## unified APIs for C and js backends,
## acting like std/syncio
when defined(nimPreviewSlimSys):
  import std/syncio

import ../Utils/[compat]
when not declared(stdout):
  import ../Utils/[compat_io_os, jsdispatch,]
  type
    FileHandle* = distinct cint
    File* = ref object
      fd: FileHandle
      name: string
  proc `==`(a, b: FileHandle): bool{.borrow.}
  proc newFile(name: string, fd = -1): File =
    result = File(fd: FileHandle fd, name: name)
  proc close*(f: File) =
    let fd = f.fd.cint
    if fd <= 2: return # -1 means closed, 0,1,2 is stdio
    f.fd = FileHandle -1

  template declStd(name, i) =
    let name* = newFile('<'&astToStr(name)&'>', i)
  declStd stdin,  0
  declStd stdout, 1
  declStd stderr, 2
  
  proc fileno*(f: File): cint = cint f.fd
  template dispatchOE(outDo, errDo): untyped = 
    if f.fd == stdout.fd: outDo
    elif f.fd == stderr.fd: errDo
    else: doAssert false
  proc writeLine*(f: File; s: string) =
    dispatchOE(echoCompat(s), errEchoCompat(s))

  #proc write*(f: File; s: string) = dispatchOE writeStdoutCompat s, writeStderrCompat s
  proc readLine*(f: File): string{.mayAsync.} =
    assert f == stdin
    mayAwait readLineCompat("")

  proc readLineFromStdin*(prompt: string): string{.mayAsync.} =
    mayAwait readLineCompat prompt
  
  proc readLine*(stdinF, stdoutF: File, prompt: string): string{.mayAsync.} =
    assert stdinF == stdin and stdoutF == stdout
    mayAwait readLineCompat prompt
  
  
  proc flushFile*(f: File) = discard
  proc flush_io*() = discard #TODO:io
  let isatty* =
    if ttyOrDeno.isNull:
      proc simp_isatty(f: cint): bool = f == 0
      simp_isatty
    else:
      proc jsvm_isatty(f: cint): bool{.importc: ttyOrDenoInJs & ".isatty".}
      jsvm_isatty

  proc readAll*(f: File): string = readFileCompat(f.name)

  proc open*(p: string, mode=FileMode.fmRead): File = newFile(p)

else:
  import ../Utils/utils
  when defined(nimPreviewSlimSys):
    import std/syncio
  when defined(wasm):
    proc readLineFromStdin*(prompt: string): string{.mayAsync.} =
      readLineCompat prompt
  else:
    import std/rdstdin
    export readLineFromStdin
  proc fileno*(f: File): cint = cint f.getFileHandle

  # condition copied from source code of rdstdin
  const notSupLinenoise = defined(windows) or defined(genode) or defined(wasm)
  when not notSupLinenoise:
    import std/linenoise
  proc readLine*(stdinF, stdoutF: File, prompt: string): string{.mayAsync.} =
    when notSupLinenoise:
      stdoutF.write prompt
      mayNewPromise stdinF.readLine()
    else:
      assert stdinF == stdin
      var res: ReadLineResult
      # readLineFromStdin cannot distinguish ctrlC and ctrlD and other error
      while true:
        readLineStatus(prompt, res)
        case res.status
        of lnCtrlC:
          #raise new InterruptError
          #errEchoCompatNoRaise"KeyboardInterrupt"
          raise new InterruptError #KeybordInterrupt
        of lnCtrlD:
          raise new EOFError
        of lnCtrlUnkown:
          # neither ctrl-c nor ctrl-d getten
          #  e.g. simple input and pass Enter
          break
      historyAdd cstring res.line
      mayNewPromise res.line
  
  proc flush_io*() =
    stderr.flushFile
    stdout.flushFile

  when defined(windows):
    proc c_isatty(fildes: cint): cint {.
      importc: "_isatty", header: "<io.h>".}
  else: #when defined(posix):
    proc c_isatty(fildes: cint): cint {.
      importc: "isatty", header: "<unistd.h>".}

  proc isatty*(fildes: cint): bool = 0 != c_isatty fildes

  export File, stdin, stdout, stderr, open

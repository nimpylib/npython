## unified APIs for C and js backends,
## acting like std/syncio
when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]
  export assertions
  export syncio

import ../Utils/[compat]
import pkg/vsyncio/extraMeth/m_isatty
export isatty
when defined(js):
  import pkg/vsyncio as nio
  export nio
  type FileHandle* = nio.FileHandle
  type File* = nio.File
  template `==`(a, b: FileHandle): bool =
    a.cint == b.cint
  
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
  
else:
  import ../Utils/utils
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
      stdoutF.flushFile
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
  
  export File, stdin, stdout, stderr, open

proc flush_io*() =
  stderr.flushFile
  stdout.flushFile


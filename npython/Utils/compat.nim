{.define: esModule.}
import pkg/jscompat/os
import pkg/vsyncio/extra/rdstdinMayAsync
export npythonJsAsyncReadline, KeyboardInterrupt
export mayAsync, mayAwait, mayWaitFor, mayNewPromise, MayPromise
from pkg/jscompat import quitCompat
export absolutePathCompat
when defined(js):
  import ./jsdispatch
  import std/jsconsole
  import pkg/vsyncio as nio
  import pkg/vsyncio/jsFile/stdio
  export nio
  const
    dKarax = defined(karax)
    jsAlert = defined(jsAlert)
  type
    Stdin  = ref object of StdioFile
    Stdout = ref object of StdioFile
    Stderr = ref object of StdioFile

  template reassignStdio {.dirty.} =
    stdin  = new[Stdin ]("<stdin>",  0, fmRead)
    stdout = new[Stdout]("<stdout>", 1, fmWrite)
    stderr = new[Stderr]("<stderr>", 2, fmWrite)

  using stdin: Stdin
  using stderr: Stderr
  using stdout: Stdout
  when jsAlert:
    reassignStdio

    proc alert(s: cstring){.importc.}
    method writeLine*(stderr; content: string) =
      let cs = cstring content
      console.error cs
      alert cs
    template echoCompat*(content: string) =
      alert cstring content
  elif dKarax:
    reassignStdio

    include karax/prelude
    var stream*: seq[(kstring, kstring)]
    template echoCompat*(content: string) =
      echo content
      stream.add((kstring"", kstring(content)))
    method readLine*(stdin; content: string) =
      doAssert false, "not impl. #TODO:io #TODO:karax: to extract readline from karaxpython.nim"
    method writeLine*(stderr; content: string) =
      echoCompat content
    proc getAppFilenameCompat*(): string = ""
    proc quitCompat*(x: int|string = 0) =
      doAssert false, "`quit` not supported on karax"
  else:
    template echoCompat*(content: string) =
      echo content
  method writeLine*(stdout; content: string) =
    echoCompat content

  when not dKarax:
    proc getCurrentDir*(): string = getCurrentDirCompat()
else:

  template echoCompat*(content) = 
    echo content

template errEchoCompat*(content) = 
  stderr.writeLine content

template readLineCompat*(prompt: string): auto =
  bind readLineFromStdinMayAsync
  readLineFromStdinMayAsync(prompt)

# Years ago...
# combining two seq directly leaded to a bug in the compiler when compiled to JS
# see gh-10651 (have been closed)
template addCompat*[T](a, b: seq[T]) = 
  a.add b
  
when not declared(getCurrentDir):
  when defined(js):
    proc getCurrentDir*(): string = ""  ## XXX: workaround for pyInit(@[])
  else:
    import std/os
    export getCurrentDir
when not declaredInScope(getAppFilenameCompat):
  export getAppFilenameCompat, quitCompat
when not compiles(quitCompat("")):
  proc quitCompat*(e: string) =
    errEchoCompat(e)
    quitCompat QuitFailure

template errEchoCompatNoRaise*(s: string) =
  bind errEchoCompat
  try: errEchoCompat s
  except IOError: discard

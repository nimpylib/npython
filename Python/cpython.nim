
import std/parseopt
import strformat

import neval
import compile
import coreconfig
import traceback
import lifecycle
import ./getversion
import ../Parser/[lexer, parser]
import ../Objects/bundle
import ../Utils/[utils, compat, getplatform]
import ../Include/internal/pycore_global_strings

proc getVersionString*(verbose=false): string =
  result = "NPython "
  if not verbose:
    result.add Version
    return
  result.add Py_GetVersion()
  result.add " on "
  result.add PLATFORM
template echoVersion(verbose=false) =
  echoCompat getVersionString(verbose)

proc pymain_header =
  if pyConfig.quiet: return
  errEchoCompat getVersionString(verbose=true)

const Fstdin = "<stdin>"

proc parseCompileEval*(input: string, lexer: Lexer, 
  rootCst: var ParseNode, prevF: var PyFrameObject, finished: var bool
  ) =
    ## stuff to change, just a compatitable layer for ./jspython
    try:
      rootCst = parseWithState(input, lexer, Mode.Single, rootCst)
    except SyntaxError:
      let e = SyntaxError(getCurrentException())
      let excpObj = fromBltinSyntaxError(e, newPyAscii(Fstdin))
      excpObj.printTb
      finished = true
      return

    if rootCst.isNil:
      return
    finished = rootCst.finished
    if not finished:
      return

    let compileRes = compile(rootCst, Fstdin)
    if compileRes.isThrownException:
      PyExceptionObject(compileRes).printTb
      return
    let co = PyCodeObject(compileRes)

    when defined(debug):
      echo co

    var globals: PyDictObject
    if prevF != nil:
      globals = prevF.globals
    else:
      globals = newPyDict()
    globals[pyDUId name] = pyDUId main
    let fun = newPyFunc(newPyAscii("Bla"), co, globals)
    let f = newPyFrame(fun)
    var retObj = f.evalFrame
    if retObj.isThrownException:
      PyExceptionObject(retObj).printTb
    else:
      prevF = f

proc interactiveShell*{.mayAsync.} =
  var finished = true
  # the root of the concrete syntax tree. Keep this when user input multiple lines
  var rootCst: ParseNode
  let lexer = newLexer(Fstdin)
  var prevF: PyFrameObject
  pymain_header()
  while true:
    var input: string
    var prompt: string
    if finished:
      prompt = ">>> "
      rootCst = nil
      lexer.clearIndent
    else:
      prompt = "... "
      assert (not rootCst.isNil)

    try:
      input = mayAwait readLineCompat(prompt)
    except EOFError, IOError:
      quitCompat(0)
    
    parseCompileEval(input, lexer, rootCst, prevF, finished)


template exit0or1(suc) = quitCompat(if suc: 0 else: 1)

proc nPython*(args: seq[string],
    fileExists: proc(fp: string): bool,
    readFile: proc(fp: string): string,
  ){.mayAsync.} =
  pyInit(args)
  if pyConfig.filepath == "":
    mayAwait interactiveShell()
  else:
    if not fileExists(pyConfig.filepath):
      echo fmt"File does not exist ({pyConfig.filepath})"
      quitCompat()
    let input = readFile(pyConfig.filepath)
    runSimpleString(input, pyConfig.filepath).exit0or1


proc echoUsage() =
  echoCompat "usage: python [option] [-c cmd | file]"

proc echoHelp() =
  echoUsage()
  echoCompat "Options:"
  echoCompat "-c cmd : program passed in as string (terminates option list)"
  echoCompat "-q     : don't print version and copyright messages on interactive startup"
  echoCompat "-V     : print the Python version number and exit (also --version)"
  echoCompat "         when given twice, print more information about the build"
  echoCompat "Arguments:"
  echoCompat "file   : program read from script file"


proc main*(cmdline: string|seq[string] = "",
    nPython: proc (args: seq[string]){.mayAsync.}){.mayAsync.} =
  proc unknownOption(p: OptParser){.noReturn.} =
    var origKey = "-"
    if p.kind == cmdLongOption: origKey.add '-'
    origKey.add p.key
    errEchoCompat "Unknown option: " & origKey
    echoUsage()
    quitCompat 2
  template noLongOption(p: OptParser) =
    if p.kind == cmdLongOption:
      p.unknownOption()
  when defined(js) and cmdline is seq[string]:
    # fix: initOptParser will call paramCount.
    #   which is only defined when -d:nodejs
    var cmdline =
      if cmdline.len == 0: @["-"]
      else: cmdline
  var
    args: seq[string]
    versionVerbosity = 0
  var p = initOptParser(cmdline,
    shortNoVal={'h', 'V', 'q', 'v'},
    # Python can be considered not to allow: -c:CODE -c=code
    longNoVal = @["help", "version"],
  )
  while true:
    p.next()
    case p.kind
    of cmdArgument:
      args.add p.key
    of cmdLongOption, cmdShortOption:
      case p.key:
      of "help", "h":
        echoHelp()
        quitCompat()
      of "version", "V":
        versionVerbosity.inc
      of "q": pyConfig.quiet = true
      of "v": pyConfig.verbose = true
      of "c":
        p.noLongOption()
        #let argv = @["-c"] & p.remainingArgs()
        let code =
          if p.val != "": p.val
          else: p.remainingArgs()[0]
        pyInit(@[])
        runSimpleString(code, "<string>").exit0or1
      of "":  # allow -
        discard
      else:
        p.unknownOption()
    of cmdEnd: break
  case versionVerbosity
  of 0: mayAwait nPython args
  of 1: echoVersion()
  else: echoVersion(verbose=true)

when isMainModule:
  import std/os # file existence
  proc wrap_nPython(args: seq[string]){.mayAsync.} =
    mayAwait nPython(args, os.fileExists, readFile)
  when defined(js):
    {.error: "python.nim is for c target. Compile jspython.nim as js target" .}

  mayWaitFor main(nPython=wrap_nPython)

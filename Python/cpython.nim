when defined(js):
  {.error: "python.nim is for c target. Compile jspython.nim as js target" .}

import strformat

import os # file existence



import neval
import compile
import coreconfig
import traceback
import lifecycle
import ./getversion
import ../Parser/[lexer, parser]
import ../Objects/bundle
import ../Utils/[utils, compat, getplatform]

proc getVersionString(verbose=false): string =
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

proc interactiveShell =
  var finished = true
  # the root of the concrete syntax tree. Keep this when user input multiple lines
  var rootCst: ParseNode
  let lexer = newLexer("<stdin>")
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
      input = readLineCompat(prompt)
    except EOFError, IOError:
      quit(0)

    try:
      rootCst = parseWithState(input, lexer, Mode.Single, rootCst)
    except SyntaxError:
      let e = SyntaxError(getCurrentException())
      let excpObj = fromBltinSyntaxError(e, newPyStr("<stdin>"))
      excpObj.printTb
      finished = true
      continue

    if rootCst.isNil:
      continue
    finished = rootCst.finished
    if not finished:
      continue

    let compileRes = compile(rootCst, "<stdin>")
    if compileRes.isThrownException:
      PyExceptionObject(compileRes).printTb
      continue
    let co = PyCodeObject(compileRes)

    when defined(debug):
      echo co

    var globals: PyDictObject
    if prevF != nil:
      globals = prevF.globals
    else:
      globals = newPyDict()
    let fun = newPyFunc(newPyString("Bla"), co, globals)
    let f = newPyFrame(fun)
    var retObj = f.evalFrame
    if retObj.isThrownException:
      PyExceptionObject(retObj).printTb
    else:
      prevF = f

template exit0or1(suc) = quit(if suc: 0 else: 1)

proc nPython(args: seq[string]) =
  pyInit(args)
  if pyConfig.filepath == "":
    interactiveShell()

  if not pyConfig.filepath.fileExists:
    echo fmt"File does not exist ({pyConfig.filepath})"
    quit()
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


when isMainModule:
  import std/parseopt

  proc unknownOption(p: OptParser){.noReturn.} =
    var origKey = "-"
    if p.kind == cmdLongOption: origKey.add '-'
    origKey.add p.key
    errEchoCompat "Unknown option: " & origKey
    echoUsage()
    quit 2
  template noLongOption(p: OptParser) =
    if p.kind == cmdLongOption:
      p.unknownOption()

  var
    args: seq[string]
    versionVerbosity = 0
  var p = initOptParser(
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
        quit()
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
        runSimpleString(code, "<string>").exit0or1
      else:
        p.unknownOption()
    of cmdEnd: break
  case versionVerbosity
  of 0: nPython args
  of 1: echoVersion()
  else: echoVersion(verbose=true)

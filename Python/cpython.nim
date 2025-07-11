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
import ../Utils/[utils, compat]


proc echoVersion(verbose=false) =
  echoCompat "NPython " & (
    if verbose: Py_GetVersion()
    else: Version
  )

proc interactiveShell =
  var finished = true
  # the root of the concrete syntax tree. Keep this when user input multiple lines
  var rootCst: ParseNode
  let lexer = newLexer("<stdin>")
  var prevF: PyFrameObject
  echoVersion()
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

proc nPython(args: seq[string]) =
  pyInit(args)
  if pyConfig.filepath == "":
    interactiveShell()

  if not pyConfig.filepath.fileExists:
    echo fmt"File does not exist ({pyConfig.filepath})"
    quit()
  let input = readFile(pyConfig.filepath)
  let retObj = runString(input, pyConfig.filepath)
  if retObj.isThrownException:
    PyExceptionObject(retObj).printTb

proc echoUsage() =
  echoCompat "usage: python [option] [file]"

proc echoHelp() =
  echoUsage()
  echoCompat "Options:"
  echoCompat "-V : print the Python version number and exit (also --version)"
  echoCompat "Arguments:"
  echoCompat "file   : program read from script file"


when isMainModule:
  import std/parseopt

  var args: seq[string]
  for kind, key, val in getopt(
    shortNoVal={'h', 'V'},
    longNoVal = @["help", "version"],
  ):
    case kind
    of cmdArgument: args.add key
    of cmdLongOption, cmdShortOption:
      case key:
      of "help", "h":
        echoHelp()
        quit()
      of "version", "V":
        echoVersion()
        quit()
      else:
        echoCompat "Unknown option: " & key
        echoUsage()
        quit 2
    of cmdEnd: assert(false) # cannot happen
  nPython args

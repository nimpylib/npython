
import std/parseopt
import strformat

import compile
import coreconfig
import lifecycle
import ./getversion
import ../Parser/[lexer, parser, apis,]
import ../Objects/bundle
import ../Utils/[utils, compat, fileio,]
import ./pythonrun
import ./pythonrun/utils
import ./main as pymain
from ./main/utils import getVersionString
export getVersionString

template echoVersion(verbose=false) =
  echoCompat getVersionString(verbose)

const Fstdin = "<stdin>"

type PyExecutor* = object
  ## unstable. for karax
  lexer: Lexer
  cst: ParseNode
  filename_obj: PyStrObject
  globals: PyDictObject
  nextPrompt*: string
  flags*: PyCompilerFlags

proc newPyExecutor*(filename = Fstdin): PyExecutor =
  ## this shall be singleton
  PyRun_InteractiveLoopPre()
  result = PyExecutor(
    lexer: newLexer(filename),
    filename_obj: newPyStr filename,
    globals: newPyDict(),
    nextPrompt: getSysPsEnc().ps1
  )

proc feedImpl(py: var PyExecutor, input: string): PyBaseErrorObject =
  # if finished (exception also means finished)
  audit_PyParser_AST py.filename_obj
  let finished = tokenize_and_cst_one(input, py.lexer, py.cst, result, py.filename_obj)
  if not finished:
    py.nextPrompt = getSysPsEnc().ps2
    return
  let rootCst = py.cst
  py.cst = nil
  retIfExc result

  let compileRes = compile(rootCst, py.filename_obj, py.flags)
  retIfExc compileRes
  let co = PyCodeObject(compileRes)

  when defined(debug):
    echo co

  retIfExc run_eval_code_with_audit(co, py.globals, py.globals)
  py.nextPrompt = getSysPsEnc().ps1

proc feed*(py: var PyExecutor, input: string) =
  # stuff to change, just a compatitable layer for ./karaxpython
  let exc = py.feedImpl input  
  if not exc.isNil:
    PyErr_Print exc


proc interactiveShell*{.mayAsync.} =
  pymain.header(pyConfig)
  let _ = mayAwait PyRun_AnyFileExFlags(stdin, Fstdin)


template exit0or1(suc) = quitCompat(if suc: 0 else: 1)


proc nPython(args: seq[string]){.mayAsync.} =
  pyInit(args)
  let filename = pyConfig.run_filename
  if filename == "":
    mayAwait interactiveShell()
  else:
    #pymain_run_file
    discard pymain.run_file(pyConfig) #TODO:exit
  #TODO:exit^C
  #if PyRuntime.signals.unhandled_keyboard_interrupt

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


proc main*(cmdline: string|seq[string] = ""){.mayAsync.} =
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
        pyConfig.run_command =
          if p.val != "": p.val
          else: p.remainingArgs()[0]
        pyInit(@[])
        PyRun_SimpleString(pyConfig.run_command).exit0or1
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
  when defined(js):
    {.error: "python.nim is for c target. Compile jspython.nim as js target" .}

  mayWaitFor main()

## like peg_api.c

import ../Include/cpython/compile
import ../Utils/[
  fileio, utils, compat,
]

import ./[
  parser, lexerTypes, lexer,
  ]

import ../Python/sysmodule/audit
import ../Python/[
  asdl, ast,
]
import ../Objects/[pyobject,
  stringobject, exceptionsImpl,
  noneobject,
]
import ../Objects/exceptions/ioerror


using fp: fileio.File

{.push raises: [].}
proc tokenize_and_cst_one*(input: string, lexer: Lexer, 
  rootCst: var ParseNode, exc: var PyBaseErrorObject, filename_obj: PyStrObject,
  ): bool =
  ## unstable. export for karax
  ## returns finished
  try:
    rootCst = parseWithState(input, lexer, Mode.Single, rootCst)
  except SyntaxError as e:
    exc = fromBltinSyntaxError(e, filename_obj)
    return true

  if rootCst.isNil:
    return false
  return rootCst.finished

type ParseErrorcode* = enum
  E_OK
  E_EOF

template interactiveHandleErrcode*(res: untyped=nil) =
  ## inner
  if errcode == E_EOF:
    return

declarePyType InteractiveSrc(base(Str)): lineNo: int
proc newPyInteractiveSrc* : PyInteractiveSrcObject = newPyInteractiveSrcSimple()  ##XXX: unstable, \
## workaround for repl lineNo tracking
##  (otherwise it will always be 1, as we create a new Lexer whose lineNo is initialized each time)

proc tokenize_and_cst(fp; filename_obj: PyStrObject; enc: string, ps1, ps2: string,
    errcode: var ParseErrorcode,
    rootCst: var ParseNode, # out. the root of the concrete syntax tree. 
    interactive_src: var PyInteractiveSrcObject,
    ): PyBaseErrorObject {.mayAsync.} =
  let lexer = newLexer($filename_obj, interactive_src.lineNo)

  var input: string
  var exc: PyBaseErrorObject

  var prompt = ps1
  # loop when user input multiple lines
  while true:
    try:
      input = mayAwait fp.readLine(stdout, prompt)  #TODO:enc encoding
      prompt = ps2
    except EOFError:
      errcode = E_EOF
      return mayNewPromise PyBaseErrorObject nil
    except IOError as e:
      return mayNewPromise PyBaseErrorObject newIOError e
    except InterruptError:
      errEchoCompatNoRaise"KeyboardInterrupt"
      continue
    if tokenize_and_cst_one(input, lexer, rootCst, exc, filename_obj):
      result = mayNewPromise exc
      break
  interactive_src.lineNo = lexer.lineNo
  retIfExc result
  result


proc run_parser_from_file_pointer(fp; mode: Mode, filename_obj: PyStrObject; enc: string, ps1, ps2: string, flags: PyCompilerFlags,
    errcode: var ParseErrorcode, interactive_src: var PyInteractiveSrcObject,
    res: var Asdlmodl
    ): PyBaseErrorObject {.mayAsync.} =
  ## roughly equal to `_PyPegen_run_parser_from_file_pointer`
  ##  for Interactive

  errcode = E_OK


  #pymain_header()
  var rootCst: ParseNode

  # _PyTokenizer_FromFile
  retIfExc tokenize_and_cst(fp, filename_obj, enc, ps1, ps2, errcode, rootCst, interactive_src)
  interactiveHandleErrcode

  try:
    res = ast(rootCst) #TODO:flags
  except SyntaxError as e:
    return mayNewPromise fromBltinSyntaxError(e, filename_obj)
  result
  #TODO:interactive_src

template wrapSynErr(filename_obj; body): untyped =
  try: body
  except SyntaxError as e:
    return fromBltinSyntaxError(e, filename_obj)

proc run_parser_from_string(str: string; mode: Mode, filename_obj: PyStrObject; flags: PyCompilerFlags,
    res: var Asdlmodl
    ): PyBaseErrorObject  =

  #pymain_header()
  let rootCst = wrapSynErr(filename_obj, parse(str, $fileName_obj, mode))

  wrapSynErr filename_obj:
    res = ast(rootCst) #TODO:flags

proc run_parser_from_file_pointer(fp; mode: Mode, filename_obj: PyStrObject; enc: string, flags: PyCompilerFlags,
    errcode: var ParseErrorcode,
    res: var Asdlmodl
    ): PyBaseErrorObject =
  let s = try: fp.readAll()
  except IOError as e: return PyBaseErrorObject newIOError e
  run_parser_from_string(s, mode, filename_obj, flags, res)

#[
  while true:
    if finished:
      prompt = ps1
      rootCst = nil
      lexer.clearIndent
    else:
      prompt = ps2
      assert (not rootCst.isNil)
    try:
      input = mayAwait fp.readLine(stdout, prompt)
    except EOFError, IOError:
      quitCompat(0)

    parseCompileEval(input, lexer, rootCst, finished)
]#

template audit_PyParser_AST*(filename_obj) =
  bind pyNone, mayNewPromise, retIfExc, audit
  retIfExc audit("compile", pyNone, filename_obj)
template audit_PyParser_AST_mayAsync*(filename_obj) =
  bind pyNone, mayNewPromise, retIfExc, audit
  retIfExc mayNewPromise audit("compile", pyNone, filename_obj)

proc PyParser_InteractiveASTFromFile*(fp; filename_obj: PyStrObject; enc: string, mode: Mode, ps1, ps2: string, flags: PyCompilerFlags,
    errcode: var ParseErrorcode, interactive_src: var PyInteractiveSrcObject,
    res: var Asdlmodl
    ): PyBaseErrorObject {.mayAsync.} =
  audit_PyParser_AST_mayAsync filename_obj
  run_parser_from_file_pointer(fp, mode, filename_obj, enc, ps1, ps2,
                                                 flags, errcode, interactive_src, res)

proc PyParser_ASTFromFile*(fp; filename_obj: PyStrObject; enc: string, mode: Mode,  flags: PyCompilerFlags,
    errcode: var ParseErrorcode,
    res: var Asdlmodl
    ): PyBaseErrorObject {.mayAsync.} =
  audit_PyParser_AST_mayAsync filename_obj
  run_parser_from_file_pointer(fp, mode, filename_obj, enc,
                                                 flags, errcode,  res)

proc PyParser_ASTFromString*(str: string; filename_obj: PyStrObject; mode: Mode, flags: PyCompilerFlags,
    res: var Asdlmodl
    ): PyBaseErrorObject =
  audit_PyParser_AST filename_obj
  run_parser_from_string(str, mode, filename_obj, flags, res)
{.pop.}

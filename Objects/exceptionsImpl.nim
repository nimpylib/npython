
import std/macros
import pyobject
import baseBundle
import ./[tupleobjectImpl, pyobject_apis, stringobject, typeobject,]
import ./[exceptions, warningobject, noneobject]
import ./exceptions/setter
import ./abstract/number
import ./abstract/sequence/tup
import ./[codeobject, frameobject]
import ../Utils/utils
import ./stringobject/strformat
import ../Include/cpython/critical_section
import ../Python/getargs/[vargs, kwargs]
import ../Parser/lexer

export exceptions
export setter

macro genMethodMacros: untyped  =
  result = newStmtList()
  for tok in ExceptionToken:
    let objName = $tok & "Error"
    result.add(getAst(methodMacroTmpl(ident(objName))))
  for tok in BaseExceptionToken:
    let objName = $tok
    result.add(getAst(methodMacroTmpl(ident(objName))))


genMethodMacros

proc BaseException_repr(self: PyBaseExceptionObject): PyObject =
  var msg: string = self.typeName
  template `add%R`(o) =
    let s = PyObject_ReprNonNil o
    retIfExc s
    msg.add $s
  if self.args.len == 1:
    msg.add '('
    `add%R` self.args[0]
    msg.add ')'
  else:
    `add%R` self.args
  newPyStr(msg)

proc BaseException_str(self: PyBaseExceptionObject): PyObject =
  if self.args.len == 0: newPyAscii()
  else: PyObject_StrNonNil(self.args[0])

template strMagicTmpl(excpName: untyped){.dirty.} = 
  `impl excpName Magic` repr: BaseException_repr self
  `impl excpName Magic` str: BaseException_str self

strMagicTmpl(BaseException)

template newMagicTmpl(excpName: untyped){.dirty.} = 
  #FIXME: rm following impl Magic
  #TODO:subclass why did not inherit from BaseException's?

  # this is for initialization at Python level
  `impl excpName Magic` New:
    let excp = `new excpName`()
    excp.thrown = false
    if args.len > 1:
      excp.args = newPyTuple(args.toOpenArray(1, args.high))
    excp

proc initBaseException*(op: PyBaseExceptionObject, args: PyTupleObject) =
  op.args = args
proc initBaseException*(op: PyBaseExceptionObject, args: openArray[PyObject]) =
  op.initBaseException(newPyTuple args)

implBaseExceptionMagic init(*args):
  initBaseException(self, newPyTuple(args))
  pyNone

implSystemExitMagic init(*args):
  let size = args.len
  let t = newPyTuple(args)
  initBaseException(self, t)
  result = pyNone
  case size
  of 0: return
  of 1:
    self.code = args[0]
  else:
    self.code = t

macro implAllowKw_init(name, kwOnlyList; extraBody) =
  ## ``(*args, *, `*kwOnlyList`)``
  ##  e.g. `(*args, *, name, path, name_from)`
  let
    nameS = $name
    nameStr = newLit nameS
  let mag = ident("impl" & nameS & "Magic")
  let body = newStmtList quote do:
    initBaseException(self, args)
  let call = newCall("PyArg_UnpackKeywordsToAs", nameStr, ident"kw")
  for i in kwOnlyList:
    call.add i
  body.add newCall("retIfExc", call)
  for n in kwOnlyList:
    body.add quote do:
      self.`n` = `n`
  body.add extraBody
  body.add bindSym"pyNone"

  result = quote do:
    `mag` init(*args, **kw): # (*, name, path, name_from):
      `body`

implAllowKw_init ImportError, {name, path, name_from}:
  if args.len == 1:
    self.msg = args[0]

implImportErrorMagic str:
  if not self.msg.isNil and self.msg.ofPyStrObject:
    return self.msg
  return BaseException_str(self)

implImportErrorMagic repr:
  var hasargs = self.args.len != 0
  if self.name.isNil and self.path.isNil:
      return BaseException_repr(self)

  let r = BaseException_repr(self)
  retIfExc r
  let rstr = $PyStrObject(r).str
  var msg = rstr[0 .. rstr.len-2]  # remove trailing ')'

  template addAttrRepr(name) =
    if not self.name.isNil:
      if hasargs:
        msg.add(", ")
      msg.add astToStr name
      msg.add '='
      let reprX = PyObject_ReprNonNil(self.name)
      retIfExc reprX
      msg.add $reprX
      hasargs = true

  addAttrRepr(name)
  addAttrRepr(path)

  msg.add(')')
  newPyStr(msg)

implOSErrorMagic init:
  initBaseException(self, args)
  #TODO:OSError
  self.written = -1
  pyNone

implOSErrorMagic str:
  template OR_NONE(x: untyped): untyped =
    if x.isNil: pyNone else: x

  template f(ts, xerr){.dirty.} =
    let s = ts
    let err = self.xerr
    if not err.isNil and not self.filename.isNil:
      return if not self.filename2.isNil:
        newPyStr&"[{s} {OR_NONE(err):S}] {OR_NONE(self.strerror):S}: {self.filename:S} -> {self.filename2:S}"
      else:
        newPyStr&"[{s} {OR_NONE(err):S}] {OR_NONE(self.strerror):S}: {self.filename:S}"
    if not err.isNil and not self.strerror.isNil:
      return newPyStr&"[{s} {err:S}] {self.strerror:S}"
  when defined(windows):
    # If available, winerror has the priority over myerrno
    f("WinError", winerror)

  # POSIX-style messages using errno/myerrno
  f("Errno", errno)

  return BaseException_str(self)

proc characters_written*(self: PyOSErrorObject): PyObject =
  if self.written == -1:
    return newAttributeError newPyAscii"characters_written"
  return newPyInt self.written

proc set_characters_written*(self: PyOSErrorObject, arg: PyObject): PyBaseErrorObject =
  if arg.isNil:
    if self.written == -1:
      return newAttributeError newPyAscii"characters_written"
    self.written = -1
    return
  let n = PyNumber_AsSsize_t(arg, pyValueErrorObjectType, result)
  if not result.isNil:
    return
  self.written = n

genProperty OSError, "characters_written", characters_written, self.characters_written:
  retIfExc self.set_characters_written(other)
  pyNone


implAllowKw_init NameError, {name}: discard

implAllowKw_init AttributeError, {name, obj}: discard

implSyntaxErrorMagic init(*args, **kw):
  let lenargs = args.len
  if lenargs >= 1:
    self.msg = args[0]
  if lenargs == 2:
    let infoObj = PySequence_Tuple args[1]
    retIfExc infoObj
    let info = PyTupleObject infoObj

    PyArg_UnpackTuple("SyntaxError",
      info, 4, 7,
      self.filename, self.lineno, self.offset, self.text,
      self.end_lineno, self.end_offset, self.metadata
    )
    if not self.end_lineno.isNil and self.end_offset.isNil:
      return newValueError newPyAscii"end_offset must be provided if end_lineno is provided"
  pyNone


proc my_basename(filename: PyObject): PyObject =
  ## equivalent to os.path.basename
  if not filename.ofPyStrObject:
    return newTypeError newPyAscii"filename must be a string or None"
  let fnameStr = $PyStrObject(filename).str
  let hi = fnameStr.len - 1
  var offset = 0
  for i in countdown(hi, 0):
    if fnameStr[i] == '/' or fnameStr[i] == '\\':
      offset = i + 1
  if offset > 0:
    let base = fnameStr[offset .. hi]
    newPyStr base
  else:
    filename

implSyntaxErrorMagic str:
  var filename: PyObject = nil

  # If filename is a unicode, use its basename (may return on error)
  if not self.filename.isNil and ofPyStrObject(self.filename):
    filename = my_basename(self.filename)
    retIfExc filename

  let have_lineno = (not self.lineno.isNil) and ofExactPyIntObject(self.lineno)

  let filenameIsNil = filename.isNil
  if filenameIsNil and not have_lineno:
    return PyObject_Str(self.msg.nil2none)

  var overflow: IntSign
  var lineno: int
  if not filenameIsNil and have_lineno:
    retIfExc PyLong_AsLongAndOverflow(self.lineno, overflow, lineno)
    newPyStr&"{self.msg.nil2none:S} ({filename:U}, line {lineno})"
  elif not filenameIsNil:
    newPyStr&"{self.msg.nil2none:S} ({filename:U})"
  else:
    retIfExc PyLong_AsLongAndOverflow(self.lineno, overflow, lineno)
    newPyStr&"{self.msg.nil2none:S} (line {lineno})"

methodMacroTmpl(KeyError)
implKeyErrorMagic str:
  #[
If args is a tuple of exactly one item, apply repr to args[0].
This is done so that e.g. the exception raised by {}[''] prints
  KeyError: ''
rather than the confusing
  KeyError
alone.  The downside is that if KeyError is raised with an explanatory
string, that string will be displayed in quotes.  Too bad.
If args is anything else, use the default BaseException__str__().]#
  if self.args.len == 1:
    return PyObject_ReprNonNil(self.args[0])
  return BaseException_str(self)

#TODO:UnicodeError

macro genNewMagic: untyped = 
  result = newStmtList()
  for tok in ExceptionToken:
    let excName = tok.getTokenName
    result.add(getAst(newMagicTmpl(ident(excName & "Error"))))
  for tok in BaseExceptionToken:
    let excName = tok.getTokenName
    result.add(getAst(newMagicTmpl(ident(excName))))


genNewMagic()



#TODO:BaseExceptionGroup

proc matchExcp*(target: PyTypeObject, current: PyExceptionObject): PyBoolObject = 
  var tp = current.pyType
  while tp != nil:
    if tp == target:
      return pyTrueObj
    tp = tp.base
  pyFalseObj


proc isExceptionType*(obj: PyObject): bool = 
  ## check if is of BaseException type
  if not (obj.pyType.kind == PyTypeToken.Type):
    return false
  let objType = PyTypeObject(obj)
  objType.kind == PyTypeToken.BaseException


declarePyType Traceback(mutable):
  tb_next_may_nil: PyTracebackObject
  tb_frame{.member, readonly.}: PyObject #PyFrameObject
  tb_lasti{.member, readonly.}: int
  tb_lineno{.member, readonly.}: int
  colNo: int  ## for syntax error, -1 otherwise

proc get_tb_next*(self: PyTracebackObject): PyObject = self.tb_next_may_nil.nil2none

proc `set_tb_next`*(self: PyTracebackObject; value: PyObject): PyBaseExceptionObject =
  if value.isNil:
      return newTypeError newPyAscii"can't delete tb_next attribute"

  #[ We accept None or a traceback object, and map None -> NULL (inverse of
      tb_next_get) ]#
  var value = value
  if value.isPyNone:
    value = nil
  elif not value.ofPyTracebackObject:
    return newTypeError newPyAscii"expected traceback object" & newPyStr(
                fmt"expected traceback object, got '{value.typeName}'"
    )

  # Check for loops
  var cursor = PyTracebackObject value
  while not cursor.isNil:
    if cursor == self:
        return newValueError newPyAscii"traceback loop detected"
    criticalWrite(cursor):
      cursor = cursor.tb_next_may_nil
  self.tb_next_may_nil = PyTracebackObject value


genProperty Traceback, "tb_next", tb_next, self.get_tb_next:
  criticalWrite(self):
    result = self.set_tb_next other

type TraceBack = tuple
  fileName: PyObject  # actually string
  funName: PyObject  # actually string
  frame: PyObject  # actually PyFrameObject type
  lineNo: int
  colNo: int  # optional, for syntax error
  lasti: int  # optional

proc newPyTraceback*(t: TraceBack): PyTracebackObject =
  result = newPyTracebackSimple()
  #result.colon = newPyInt t.colNo
  let f = PyFrameObject(t.frame)
  f.lineno = t.lineNo  #TODO:PyFrame_GetLineNumber
  result.tb_frame = f
  let code = f.code
  code.codeName = PyStrObject t.funName
  code.fileName = PyStrObject t.fileName
  result.colNo = t.colNo
  result.tb_lasti = t.lasti
  result.tb_lineno = t.lineNo

proc addTraceBack*(exc: PyBaseExceptionObject,
                         fileName, funName: PyObject,
                         lineNo, colNo: int, frame: PyObject, lastI = -1) =
  let tb: TraceBack = (fileName: fileName,
                      funName: funName,
                      frame: frame,
                      lineNo: lineNo,
                      colNo: colNo, lasti: lastI)
  let t = newPyTraceback(tb)
  # exc.addTraceBack t
  let old = PyTracebackObject(exc.privateGetTracebackRef)
  t.tb_next_may_nil = old
  exc.privateGetTracebackRef = t

proc getSource*(filename: PyStrObject, lineNo: int, source_obj: var (PyStrObject|PyObject)): PyBaseErrorObject =
  var source: string
  case getSource($filename.str, lineNo, source)
  of GSR_Success:
    discard
  #[
  of GSR_LineNoNotSet:
    source = "<no source line available>"
  of GSR_LineNoOutOfRange:
    source = &"<no source line available (line number {lineno} out of range {source})>"
  of GSR_NoSuchFile:
    source = "<no source line available (file not found)>"
  ]#
  of GSR_LineNoNotSet, GSR_LineNoOutOfRange:
    return newIndexError newPyAscii"line number out of range"
  of GSR_NoSuchFile:
    return newIOError newPyAscii "no such file"
  source_obj = newPyStr source

proc fromBltinSyntaxError*(e: SyntaxError, fileName: PyStrObject): PyExceptionObject = 
  let smsg = newPyStr(e.msg)
  let excpObj = newSyntaxError smsg
  let lineNo = newPyInt e.lineNo
  excpObj.lineno = lineNo

  #TODO:end_lineno
  #excpObj.end_lineno = lineNo

  excpObj.filename = fileName
  let offset = newPyInt e.colNo
  excpObj.offset = offset

  #TODO:end_offset
  #excpObj.end_offset = newPyInt(e.colNo + 1)
  excpObj.msg = smsg

  retIfExc getSource(fileName, e.lineNo, excpObj.text)

  # don't have code name
  #[
    #TODO:SyntaxError
    #TODO:tstate
    our SyntaxError missing frame, as we didn't store current_exception in some global state
    We shall use `setObject` so frame here won't be nil
  ]#
  let f = newPyFrame()
  f.lineno = e.lineNo
  f.code = newPyCode(
    fileName,
    fileName,
    0
  )
  excpObj.addTraceBack(fileName, nil, e.lineNo, e.colNo, f)
  excpObj


template ITEM(excName: untyped): untyped =
  #(exc:
    `py excName ObjectType`
  #, name: astToStr(excName))

let static_exceptions = [
    ITEM(BaseException),

    # Level 2: BaseException subclasses
    ITEM(BaseExceptionGroup),
    ITEM(Exception),
    ITEM(GeneratorExit),
    ITEM(KeyboardInterrupt),
    ITEM(SystemExit),

    # Level 3: Exception(BaseException) subclasses
    ITEM(ArithmeticError),
    ITEM(AssertionError),
    ITEM(AttributeError),
    ITEM(BufferError),
    ITEM(EOFError),
    #//ITEM(ExceptionGroup),
    ITEM(ImportError),
    ITEM(LookupError),
    ITEM(MemoryError),
    ITEM(NameError),
    ITEM(OSError),
    ITEM(ReferenceError),
    ITEM(RuntimeError),
    ITEM(StopAsyncIteration),
    ITEM(StopIteration),
    ITEM(SyntaxError),
    ITEM(SystemError),
    ITEM(TypeError),
    ITEM(ValueError),
    ITEM(Warning),

    # Level 4: ArithmeticError(Exception) subclasses
    ITEM(FloatingPointError),
    ITEM(OverflowError),
    ITEM(ZeroDivisionError),

    # Level 4: Warning(Exception) subclasses
    ITEM(BytesWarning),
    ITEM(DeprecationWarning),
    ITEM(EncodingWarning),
    ITEM(FutureWarning),
    ITEM(ImportWarning),
    ITEM(PendingDeprecationWarning),
    ITEM(ResourceWarning),
    ITEM(RuntimeWarning),
    ITEM(SyntaxWarning),
    ITEM(UnicodeWarning),
    ITEM(UserWarning),

    # Level 4: OSError(Exception) subclasses
    ITEM(BlockingIOError),
    ITEM(ChildProcessError),
    ITEM(ConnectionError),
    ITEM(FileExistsError),
    ITEM(FileNotFoundError),
    ITEM(InterruptedError),
    ITEM(IsADirectoryError),
    ITEM(NotADirectoryError),
    ITEM(PermissionError),
    ITEM(ProcessLookupError),
    ITEM(TimeoutError),

    # Level 4: Other subclasses
    ITEM(IndentationError), # base: SyntaxError(Exception)
    #{&_PyExc_IncompleteInputError, "_IncompleteInputError"}, # base: SyntaxError(Exception)
    ITEM(IndexError),  # base: LookupError(Exception)
    ITEM(KeyError),  # base: LookupError(Exception)
    ITEM(ModuleNotFoundError), # base: ImportError(Exception)
    ITEM(NotImplementedError),  # base: RuntimeError(Exception)
    ITEM(PythonFinalizationError),  # base: RuntimeError(Exception)
    ITEM(RecursionError),  # base: RuntimeError(Exception)
    ITEM(UnboundLocalError), # base: NameError(Exception)
    ITEM(UnicodeError),  # base: ValueError(Exception)

    # Level 5: ConnectionError(OSError) subclasses
    ITEM(BrokenPipeError),
    ITEM(ConnectionAbortedError),
    ITEM(ConnectionRefusedError),
    ITEM(ConnectionResetError),

    # Level 5: IndentationError(SyntaxError) subclasses
    ITEM(TabError),  # base: IndentationError

    # Level 5: UnicodeError(ValueError) subclasses
    ITEM(UnicodeDecodeError),
    ITEM(UnicodeEncodeError),
    ITEM(UnicodeTranslateError),
]

proc PyExc_InitTypes*(): PyBaseErrorObject =
  ## `_PyExc_InitTypes`
  for exc in static_exceptions:
    retIfExc PyStaticType_InitBuiltin exc


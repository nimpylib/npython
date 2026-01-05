import pyobject
import baseBundle
import ./[tupleobjectImpl, pyobject_apis, stringobject,]
import ./exceptions
import ./[codeobject, frameobject]
import ../Utils/utils
import ./stringobject/strformat
import ../Include/cpython/critical_section

export exceptions

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

template newMagicTmpl(excpName: untyped){.dirty.} = 
  #FIXME: rm following impl Magic
  #TODO:subclass why did not inherit from BaseException's?
  `impl excpName Magic` repr: BaseException_repr self
  `impl excpName Magic` str: BaseException_str self

  # this is for initialization at Python level
  `impl excpName Magic` New:
    let excp = `new excpName`()
    excp.thrown = false
    if args.len > 1:
      excp.args = newPyTuple(args.toOpenArray(1, args.high))
    excp


macro genNewMagic: untyped = 
  result = newStmtList()
  for tok in ExceptionToken:
    let excName = tok.getTokenName
    result.add(getAst(newMagicTmpl(ident(excName & "Error"))))
  for tok in BaseExceptionToken:
    let excName = tok.getTokenName
    result.add(getAst(newMagicTmpl(ident(excName))))


genNewMagic()


proc initBaseException*(op: PyBaseExceptionObject, args: PyTupleObject) =
  op.args = args

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


proc fromBltinSyntaxError*(e: SyntaxError, fileName: PyStrObject): PyExceptionObject = 
  let smsg = newPyStr(e.msg)
  let excpObj = newSyntaxError smsg
  excpObj.lineno = newPyInt e.lineNo
  #TODO:end_lineno
  excpObj.filename = fileName
  excpObj.end_offset = newPyInt e.colNo
  excpObj.msg = smsg
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

proc setString*(e: PyBaseExceptionObject, m: PyStrObject) =
  withSetItem e.args, acc: acc[0] = m
proc setString*(e: PyBaseExceptionObject, m: string) =
  ## `_PyErr_SetString`
  e.setString newPyStr m

func ofPyExceptionClass*(x: PyTypeObject): bool =
  x.kind == PyTypeToken.BaseException

template ofPyExceptionClass*(x: PyObject): bool =
  ## `PyExceptionClass_Check`
  if not x.ofPyTypeObject: return
  ofPyExceptionClass(PyTypeObject(x))

func ofPyExceptionInstance*(x: PyObject): bool =
  ## `PyExceptionInstance_Check`  
  ofPyExceptionClass x.pytype

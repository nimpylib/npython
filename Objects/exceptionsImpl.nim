import pyobject
import baseBundle
import ./[tupleobjectImpl, pyobject_apis]
import ./exceptions
import ../Utils/utils
import ./stringobject/strformat

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


proc fromBltinSyntaxError*(e: SyntaxError, fileName: PyStrObject): PyExceptionObject = 
  let smsg = newPyStr(e.msg)
  let excpObj = newSyntaxError smsg
  excpObj.lineno = newPyInt e.lineNo
  #TODO:end_lineno
  excpObj.filename = fileName
  excpObj.end_offset = newPyInt e.colNo
  excpObj.msg = smsg
  # don't have code name
  excpObj.traceBacks.add (PyObject fileName, PyObject nil, e.lineNo, e.colNo)
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

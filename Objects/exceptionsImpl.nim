import pyobject
import baseBundle
import ./[tupleobjectImpl, pyobject_apis]
import exceptions
import ../Utils/utils

export exceptions

macro genMethodMacros: untyped  =
  result = newStmtList()
  for i in ExceptionToken.low..ExceptionToken.high:
    let objName = $ExceptionToken(i) & "Error"
    result.add(getAst(methodMacroTmpl(ident(objname))))


genMethodMacros

proc BaseException_repr(self: PyBaseErrorObject): PyObject =
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

proc BaseException_str(self: PyBaseErrorObject): PyObject =
  if self.args.len == 0: newPyAscii()
  else: PyObject_StrNonNil(self.args[0])

template newMagicTmpl(excpName: untyped){.dirty.} = 

  `impl excpName ErrorMagic` repr: BaseException_repr self
  `impl excpName ErrorMagic` str: BaseException_str self

  # this is for initialization at Python level
  `impl excpName ErrorMagic` New:
    let excp = `new excpName Error`()
    excp.thrown = false
    if args.len > 1:
      excp.args = newPyTuple(args.toOpenArray(1, args.high))
    excp


macro genNewMagic: untyped = 
  result = newStmtList()
  for i in ExceptionToken.low..ExceptionToken.high:
    let excName = ExceptionToken(i).getTokenName
    result.add(getAst(newMagicTmpl(ident(excName))))


genNewMagic()


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

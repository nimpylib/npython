import pyobject
import baseBundle
import ./[tupleobjectImpl, stringobjectImpl]
import exceptions
import ../Utils/utils

export exceptions

macro genMethodMacros: untyped  =
  result = newStmtList()
  for i in ExceptionToken.low..ExceptionToken.high:
    let objName = $ExceptionToken(i) & "Error"
    result.add(getAst(methodMacroTmpl(ident(objname))))


genMethodMacros


template newMagicTmpl(excpName: untyped, excpNameStr: string){.dirty.} = 

  `impl excpName ErrorMagic` repr:
    # must return pyStringObject, used when formatting traceback
    var msg: string
    assert not self.args.isNil
    # ensure this is either an throwned exception or string for user-defined type
    let msgObj = self.args.callMagic(repr)
    if msgObj.isThrownException:
      msg = "evaluating __repr__ failed"
    else:
      msg = $PyStrObject(msgObj)
    let str = $self.tk & "Error: " & msg
    newPyStr(str)
  `impl excpName ErrorMagic` str:
    if self.args.len == 0: newPyAscii()
    else: PyObject_StrNonNil(self.args[0])


  # this is for initialization at Python level
  `impl excpName ErrorMagic` New:
    let excp = `newPy excpName ErrorSimple`()
    excp.tk = ExceptionToken.`excpName`
    excp.args = newPyTuple(args)
    excp


macro genNewMagic: untyped = 
  result = newStmtList()
  for i in ExceptionToken.low..ExceptionToken.high:
    let tokenStr = $ExceptionToken(i)
    result.add(getAst(newMagicTmpl(ident(tokenStr), tokenStr & "Error")))


genNewMagic()


proc matchExcp*(target: PyTypeObject, current: PyExceptionObject): PyBoolObject = 
  var tp = current.pyType
  while tp != nil:
    if tp == target:
      return pyTrueObj
    tp = tp.base
  pyFalseObj


proc isExceptionType*(obj: PyObject): bool = 
  if not (obj.pyType.kind == PyTypeToken.Type):
    return false
  let objType = PyTypeObject(obj)
  objType.kind == PyTypeToken.BaseError


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

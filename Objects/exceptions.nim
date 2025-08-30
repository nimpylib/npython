# we use a completely different approach for error handling
# CPython relies on NULL as return value to inform the caller 
# that exception happens in that function. 
# Using NULL or nil as "expected" return value is bad idea
# let alone using global variables so
# we return exception object directly with a thrown flag inside
# This might be a bit slower but we are not pursueing ultra performance anyway
import std/enumutils
import std/macrocache
import std/tables
export macrocache.items
from std/strutils import split
import std/strformat

import ./[pyobject, stringobject, noneobject, tupleobject]


type ExceptionToken* {. pure .} = enum
  Base,
  Name,
  Type,
  Arithmetic,
  Attribute,
  Value,
  Lookup,
  StopIter,
  Lock,
  Import,
  Assertion,
  Runtime,
  Syntax, #TODO:SyntaxError: shall be with many attributes
  Memory,
  KeyboardInterrupt,  #TODO:BaseException shall be subclass of BaseException
  System,

const ExcAttrs = toTable {
  # values will be `split(',')`
  Name: "name",
  Attribute: "name,obj",
  StopIter: "value",
  Import: "msg,name,name_from,path",
  Syntax: "end_lineno,end_offset,filename,lineno,msg,offset,print_file_and_line,text"
}
iterator extraAttrs(tok: ExceptionToken): NimNode =
  ExcAttrs.withValue(tok, value):
    for n in value.split(','):
      yield ident n

proc getTokenName*(excp: ExceptionToken): string = excp.symbolName
proc getBltinName*(excp: ExceptionToken): string =
  case excp
  of Base: "Exception"
  of StopIter: "StopIteration"
  else: excp.getTokenName & "Error"

type TraceBack* = tuple
  fileName: PyObject  # actually string
  funName: PyObject  # actually string
  lineNo: int
  colNo: int  # optional, for syntax error


declarePyType BaseError(tpToken, typeName("Exception")):
  tk: ExceptionToken
  thrown: bool
  args: PyTupleObject  # could not be nil
  context: PyBaseErrorObject  # if the exception happens during handling another exception
  # used for tracebacks, set in neval.nim
  traceBacks: seq[TraceBack]


type
  PyExceptionObject* = PyBaseErrorObject


proc ofPyExceptionObject*(obj: PyObject): bool {. cdecl, inline .} = 
  obj.ofPyBaseErrorObject

macro setAttrsNone(tok: static[ExceptionToken], self) =
  result = newStmtList()
  for n in extraAttrs(tok):
    result.add newAssignment(
      newDotExpr(self, n),
      bindSym"pyNone"
    )

template addTp(tp; basetype) = 
  tp.kind = PyTypeToken.BaseError
  tp.base = basetype
template addTpOfBaseWithName(name) = 
  addTp `py name ErrorObjectType`, pyBaseErrorObjectType

macro declareErrors: untyped = 
  result = newStmtList()
  for i in 1..int(ExceptionToken.high):
    let tok = ExceptionToken(i)
    let tokenStr = tok.getTokenName
    var attrs = newStmtList()
    for n in extraAttrs(tok):
      attrs.add newCall(
        nnkPragmaExpr.newTree(n, nnkPragma.newTree(ident"member")),
        newStmtList bindSym"PyObject")
    if attrs.len == 0:  # no extra attr
      attrs.add nnkDiscardStmt.newTree(newEmptyNode())
    let typeNode = nnkStmtList.newTree(
      nnkCommand.newTree(
        newIdentNode("declarePyType"),
        nnkCall.newTree(
          newIdentNode(tokenStr & "Error"),
          newCall(
            newIdentNode("base"),
            bindSym("BaseError")
          ),
          newCall(
            ident"typeName",
            ident tok.getBltinName  # or it'll be e.g. "stopitererror"
          )
        ),
        attrs
      )
    )

    result.add(typeNode)

    result.add(getAst(addTpOfBaseWithName(ident(tokenStr))))


declareErrors

template newProcTmpl(excpName, tok){.dirty.} = 
  # use template for lazy evaluation to use PyString
  # theses two templates are used internally to generate errors (default thrown)
  proc `new excpName Error`*: `Py excpName ErrorObject`{.inline.} = 
    let excp = `newPy excpName ErrorSimple`()
    excp.tk = ExceptionToken.`tok`
    excp.thrown = true
    setAttrsNone ExceptionToken.tok, excp
    excp

  proc `new excpName Error`*(msgStr: PyStrObject): `Py excpName ErrorObject`{.inline.} = 
    let excp = `new excpName Error`()
    excp.args = newPyTuple [PyObject msgStr]
    excp

template newProcTmpl(excpName) = 
  newProcTmpl(excpName, excpName)

macro genNewProcs: untyped = 
  result = newStmtList()
  for i in ExceptionToken.low..ExceptionToken.high:
    let tokenStr = ExceptionToken(i).getTokenName
    result.add(getAst(newProcTmpl(ident(tokenStr))))


genNewProcs

var subErrs*{.compileTime.}: seq[string]
macro declareSubError(E, baseE) =
  let
    eeS = E.strVal & "Error"
    ee = ident eeS
    bee = ident baseE.strVal & "Error"
    typ = ident "py" & ee.strVal & "ObjectType"
    btyp = ident "py" & bee.strVal & "ObjectType"
  subErrs.add eeS
  result = quote do:
    declarePyType `ee`(base(`bee`)): discard
    newProcTmpl(`E`, `baseE`)
    `addTp`(`typ`, `btyp`)
    `typ`.name = `eeS`

declareSubError Overflow, Arithmetic
declareSubError ZeroDivision, Arithmetic
declareSubError Index, Lookup
declareSubError Key, Lookup
declareSubError UnboundLocal, Name
declareSubError NotImplemented, Runtime

template newAttributeError*(tobj: PyObject, attrName: PyStrObject): untyped =
  let msg = newPyStr(tobj.pyType.name) & newPyAscii" has no attribute " & attrName
  let exc = newAttributeError(msg)
  exc.name = attrName
  exc.obj = tobj
  exc

template newIndexTypeError*(typeName: PyStrObject, obj:PyObject): untyped =
  let name = obj.pyType.name
  let msg = typeName & newPyAscii(" indices must be integers or slices, not ") & newPyStr name
  newTypeError(msg)


proc isExceptionOf*(obj: PyObject, tk: ExceptionToken): bool =
  if not obj.ofPyExceptionObject:
    return false
  let excp = PyExceptionObject(obj)
  return (excp.tk == tk) and (excp.thrown)

proc isStopIter*(obj: PyObject): bool = obj.isExceptionOf StopIter

method `$`*(e: PyExceptionObject): string = 
  result = "Error: " & $e.tk & " "
  # not e.args.isNil
  result &= $e.args



template isThrownException*(pyObj: PyObject): bool = 
  if pyObj.ofPyExceptionObject:
    cast[PyExceptionObject](pyObj).thrown
  else:
    false

template retIt = return it
template errorIfNot*(S; expect: string, pyObj: PyObject, methodName: string, doIt: untyped=retIt) = 
  if not pyObj.`ofPy S Object`:
    let typeName {. inject .} = pyObj.pyType.name
    let texp {.inject.} = expect
    let msg = methodName & fmt" returned non-{texp} (type {typeName})"
    let it {.inject.} = newTypeError newPyStr(msg)
    doIt

template errorIfNotString*(pyObj: untyped, methodName: string, doIt: untyped=retIt) = 
  errorIfNot Str, "string", pyObj, methodName, doIt

template errorIfNot*(S; pyObj: PyObject, methodName: string, doIt: untyped=retIt) = 
  errorIfNot S, astToStr(S), pyObj, methodName, doIt
template errorIfNotBool*(pyObj: PyObject, methodName: string, doIt: untyped=retIt) = 
  errorIfNot bool, pyObj, methodName, doIt

template retIfExc*(e: PyBaseErrorObject) =
  let exc = e
  if not exc.isNil:
    return exc

template retIfExc*(e: PyObject) =
  let exc = e
  if exc.isThrownException:
    return PyBaseErrorObject exc

template getIterableWithCheck*(obj: PyObject): (PyObject, UnaryMethod) = 
  var retTuple: (PyObject, UnaryMethod)
  block body:
    let iterFunc = obj.getMagic(iter)
    if iterFunc.isNil:
      let msg = obj.pyType.name & " object is not iterable"
      retTuple = (newTypeError(newPyStr msg), nil)
      break body
    let iterObj = iterFunc(obj)
    let iternextFunc = iterObj.getMagic(iternext)
    if iternextFunc.isNil:
      let msg = fmt"iter() returned non-iterator of type " & iterObj.pyType.name
      retTuple = (newTypeError(newPyStr msg), nil)
      break body
    retTuple = (iterobj, iternextFunc)
  retTuple

proc errArgNumImpl(nargs: int, expected: int, preExp: string, name=cstring""): PyTypeErrorObject=
  let suffix = if expected == 1: "" else: "s"
  var msg: string
  if name != "":
    msg = fmt"{name} takes {preExp} {expected} argument{suffix} ({nargs} given)"
  else:
    msg = fmt"expected {preExp} {expected} argument{suffix}, got {nargs}"
  return newTypeError(newPyStr msg)

template errArgNum*(argsLen, expected: int; name="")=
  bind errArgNumImpl
  return errArgNumImpl(argsLen, expected, "exactly", name)

template checkArgNum*(expected: int, name="") = 
  bind errArgNum
  if args.len != expected:
    errArgNum args.len, expected, name


template checkArgNumAtLeast*(expected: int, name="") = 
  bind errArgNumImpl
  if args.len < expected:
    return errArgNumImpl(args.len, expected, "at least", name)

template checkArgNumAtMost*(expected: int, name="") =
  bind errArgNumImpl
  if args.len > expected:
    return errArgNumImpl(args.len, expected, "at most", name)

template checkArgNum*(min, max: int, name="") =
  checkArgNumAtLeast(min, name)
  checkArgNumAtMost(max, name)

proc PyErr_Format*[E: PyBaseErrorObject](exc: E, msg: PyStrObject) =
  exc.args = newPyTuple [PyObject msg]
  when compiles(exc.msg):
    exc.msg = msg

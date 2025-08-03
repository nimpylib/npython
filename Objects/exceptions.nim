# we use a completely different approach for error handling
# CPython relies on NULL as return value to inform the caller 
# that exception happens in that function. 
# Using NULL or nil as "expected" return value is bad idea
# let alone using global variables so
# we return exception object directly with a thrown flag inside
# This might be a bit slower but we are not pursueing ultra performance anyway
import std/enumutils
import std/macrocache
export macrocache.items
import strformat

import pyobject
import stringobject


type ExceptionToken* {. pure .} = enum
  Base,
  Name,
  NotImplemented,
  Type,
  Arithmetic,
  Attribute,
  Value,
  Index,
  StopIter,
  Lock,
  Import,
  UnboundLocal,
  Key,
  Assertion,
  ZeroDivision,
  Runtime,
  Syntax,
  Memory,
  KeyboardInterrupt,

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
  msg: PyObject  # could be nil
  context: PyBaseErrorObject  # if the exception happens during handling another exception
  # used for tracebacks, set in neval.nim
  traceBacks: seq[TraceBack]


type
  PyExceptionObject* = PyBaseErrorObject


proc ofPyExceptionObject*(obj: PyObject): bool {. cdecl, inline .} = 
  obj.ofPyBaseErrorObject


macro declareErrors: untyped = 
  result = newStmtList()
  for i in 1..int(ExceptionToken.high):
    let tok = ExceptionToken(i)
    let tokenStr = tok.getTokenName

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
        nnkStmtList.newTree(
          nnkDiscardStmt.newTree(
            newEmptyNode()
          )
        )
      )
    )

    result.add(typeNode)

    template addTpTmpl(name) = 
      `py name ErrorObjectType`.kind = PyTypeToken.BaseError
      `py name ErrorObjectType`.base = pyBaseErrorObjectType

    result.add(getAst(addTpTmpl(ident(tokenStr))))


declareErrors

template newProcTmpl(excpName, tok){.dirty.} = 
  # use template for lazy evaluation to use PyString
  # theses two templates are used internally to generate errors (default thrown)
  proc `new excpName Error`*: `Py excpName ErrorObject`{.inline.} = 
    let excp = `newPy excpName ErrorSimple`()
    excp.tk = ExceptionToken.`tok`
    excp.thrown = true
    excp

  proc `new excpName Error`*(msgStr: PyStrObject): `Py excpName ErrorObject`{.inline.} = 
    let excp = `new excpName Error`()
    excp.msg = msgStr
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
    `typ`.base = `btyp`
    `typ`.name = `eeS`

declareSubError Overflow, Arithmetic

template newAttributeError*(tpName, attrName: PyStrObject): untyped =
  let msg = tpName & newPyAscii" has no attribute " & attrName
  newAttributeError(msg)

template newAttributeError*(tpName, attrName: string): untyped =
  newAttributeError(tpName.newPyStr, attrName.newPyStr)


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
  if not e.msg.isNil:
    result &= $e.msg



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

template errArgNum*(argsLen, expected: int; name="")=
  bind fmt, newTypeError, newPyStr
  var msg: string
  let sargsLen{.inject.} = $argsLen
  if name != "":
    msg = name & " takes exactly " & $expected & fmt" argument ({sargsLen} given)"
  else:
    msg = "expected " & $expected & fmt" argument ({sargsLen} given)"
  return newTypeError(newPyStr msg)

template checkArgNum*(expected: int, name="") = 
  bind errArgNum
  if args.len != expected:
    errArgNum args.len, expected, name


template checkArgNumAtLeast*(expected: int, name="") = 
  bind fmt, newTypeError, newPyStr
  if args.len < expected:
    var msg: string
    if name != "":
      msg = name & " takes at least " & $expected & fmt" argument ({args.len} given)"
    else:
      msg = "expected at least " & $expected & fmt" argument ({args.len} given)"
    return newTypeError(newPyStr msg)

proc PyErr_Format*(exc: PyBaseErrorObject, msg: PyStrObject) =
  exc.msg = msg

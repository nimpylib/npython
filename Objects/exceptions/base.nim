# we use a completely different approach for error handling
# CPython relies on NULL as return value to inform the caller 
# that exception happens in that function. 
# Using NULL or nil as "expected" return value is bad idea
# let alone using global variables so
# we return exception object directly with a thrown flag inside
# This might be a bit slower but we are not pursueing ultra performance anyway
import std/enumutils

import ../[pyobject, stringobject, noneobject]
include ./common_h
import ./[basetok, utils]
export ExceptionToken


proc getTokenName*(excp: ExceptionToken|BaseExceptionToken): string = excp.symbolName
proc getTokenNameWithError(tok: ExceptionToken): string = tok.getTokenName & "Error"
proc getBltinName*(excp: ExceptionToken): string =
  case excp
  of Base: "Exception"
  of StopIter: "StopIteration"
  else: excp.getTokenNameWithError
proc getBltinName*(excp: BaseExceptionToken): string = excp.symbolName

type TraceBack* = tuple
  fileName: PyObject  # actually string
  funName: PyObject  # actually string
  lineNo: int
  colNo: int  # optional, for syntax error


declarePyType BaseException(tpToken):
  base_tk: BaseExceptionToken
  thrown: bool
  # the following is defined `BaseException_getset` in CPython
  args{.member.}: PyTupleObject  # could not be nil
  context{.dunder_member.}: PyBaseExceptionObject  # if the exception happens during handling another exception
  # used for tracebacks, set in neval.nim
  traceBacks#[#TODO:{.member("__traceback__").}]#: seq[TraceBack]

declarePyType Exception(base(BaseException)):
  tk: ExceptionToken
##[PyBaseErrorObject is old alias in NPython,
and this makes it consist as so that all exceptions are in form of `XxxError`
]##
template alias(dest, src){.dirty.} =
  type `Py dest Object`* = `Py src Object`
  let `py dest ObjectType`* = `py src ObjectType`
  template `newPy dest Simple`*(): untyped = `newPy src Simple`()

alias BaseError, Exception

proc genTypeDeclareImpl(tok: ExceptionToken|BaseExceptionToken, nimTypeName, pyTypeName: NimNode): NimNode =
    var attrs = newStmtList()
    for n in extraAttrs(tok):
      attrs.add newCall(
        nnkPragmaExpr.newTree(n, nnkPragma.newTree(ident"member")),
        newStmtList bindSym"PyObject")
    if attrs.len == 0:  # no extra attr
      attrs.add nnkDiscardStmt.newTree(newEmptyNode())
    nnkStmtList.newTree(
      nnkCommand.newTree(
        newIdentNode("declarePyType"),
        nnkCall.newTree(
          nimTypeName,
          newCall(
            newIdentNode("base"),
            bindSym("Exception")
          ),
          newCall(
            ident"typeName",
            pyTypeName  # or it'll be e.g. "stopitererror"
          )
        ),
        attrs
      )
    )

template addTypeDeclare(result: var NimNode, tok: ExceptionToken|BaseExceptionToken, nimTypeName, pyTypeName: NimNode) =
  result.add(genTypeDeclareImpl(tok, nimTypeName, pyTypeName))
  result.add(getAst(addTpOfBaseWithName(nimTypeName)))

macro declareExceptions =
  result = newStmtList()
  for i in 1..int(ExceptionToken.high):
    let tok = ExceptionToken(i)
    let
      nimTypeName = ident(tok.getTokenNameWithError)
      pyTypeName = ident tok.getBltinName

    result.addTypeDeclare(tok, nimTypeName, pyTypeName)

macro declareBaseExceptions =
  result = newStmtList()
  for i in 1..int(BaseExceptionToken.high):
    let tok = BaseExceptionToken(i)
    let typeName = ident tok.getTokenName
    result.addTypeDeclare(tok, typeName, typeName)

declareExceptions
declareBaseExceptions

alias StopIteration, StopIterError

template genNewProcsOf(T; nimTypeNameGetter){.dirty.} =
  macro `genNewProcs T` = 
    result = newStmtList()
    for tok in T:
      let
        tokenStr = ident nimTypeNameGetter(tok)
        enumVal = newLit tok
      result.add quote do:
        `newProcTmpl`(`tokenStr`, `enumVal`)
  `genNewProcs T`
  

genNewProcsOf ExceptionToken, getTokenNameWithError
genNewProcsOf BaseExceptionToken, getTokenName


proc isExceptionOf*(obj: PyObject, tk: ExceptionToken): bool =
  if not obj.ofPyExceptionObject:
    return false
  let excp = PyExceptionObject(obj)
  return (excp.tk == tk) and (excp.thrown)

proc isStopIter*(obj: PyObject): bool = obj.isExceptionOf StopIter

method `$`*(e: PyExceptionObject): string {.raises: [].} = 
  result = "Error: " & $e.tk & " "
  # not e.args.isNil
  result &= $e.args




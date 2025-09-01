# we use a completely different approach for error handling
# CPython relies on NULL as return value to inform the caller 
# that exception happens in that function. 
# Using NULL or nil as "expected" return value is bad idea
# let alone using global variables so
# we return exception object directly with a thrown flag inside
# This might be a bit slower but we are not pursueing ultra performance anyway
import std/enumutils

import ../[pyobject, stringobject, noneobject, tupleobject]
import ./[basetok, utils]
export ExceptionToken


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


macro genNewProcs: untyped = 
  result = newStmtList()
  for i in ExceptionToken.low..ExceptionToken.high:
    let tokenStr = ExceptionToken(i).getTokenName
    result.add(getAst(newProcTmpl(ident(tokenStr))))


genNewProcs



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




import strformat
{.used.}  # this module contains toplevel code, so never `importButNotUsed`
import neval
import builtindict
import ./compile
import ../Objects/[bundle, typeobjectImpl, methodobject, descrobject, funcobject,
  notimplementedobject, sliceobjectImpl, dictobjectImpl, exceptions,
  byteobjectsImpl, noneobjectImpl, descrobjectImpl, pyobject_apis,
  listobject, enumobject,
  ]


import ../Utils/[utils, macroutils, compat]


proc registerBltinFunction(name: string, fun: BltinFunc) = 
  let nameStr = newPyAscii(name)
  assert (not bltinDict.hasKey(nameStr))
  bltinDict[nameStr] = newPyNimFunc(fun, nameStr)


proc registerBltinObject(name: string, obj: PyObject) = 
  let nameStr = newPyAscii(name)
  assert (not bltinDict.hasKey(nameStr))
  bltinDict[nameStr] = obj

# make it public so that neval.nim can use it
macro implBltinFunc*(prototype, pyName, body: untyped): untyped = 
  var (methodName, argTypes) = getNameAndArgTypes(prototype)
  let name = ident("bltin" & $methodName)

  let procNode = newProc(
    nnkPostFix.newTree(
      ident("*"),  # let other modules call without having to lookup in the bltindict
      name,
    ),
    bltinFuncParams.deepCopy,
    body, # the function body
  )

  procNode.addPragma(
    nnkExprColonExpr.newTree(
      ident("checkArgTypes"),
      nnkPar.newTree(
        methodName,
        argTypes
      ) 
    )
  )

  procNode.addPragma(bindSym("pyCFuncPragma"))

  var registerName: string
  if pyName.strVal == "":
    registerName = methodName.strVal
  else:
    registerName = pyName.strVal
  result = newStmtList(
    procNode,
    nnkCall.newTree(
      ident("registerBltinFunction"),
      newLit(registerName),
      name
    )
  )

macro implBltinFunc(prototype, body:untyped): untyped = 
  getAst(implBltinFunc(prototype, newLit(""), body))


# haven't thought of how to deal with infinite num of args yet
# kwargs seems to be neccessary. So stay this way for now
# luckily it does not require much boilerplate

const NewLine = "\n"
proc builtinPrint*(args: seq[PyObject]): PyObject {. cdecl .} =
  const
    sep = " "
    endl = NewLine

  const noWrite = not declared(writeStdoutCompat)
  when noWrite:
    var res: string
    template writeStdoutCompat(s) = res.add s
  template toStr(obj): string =
    let objStr = PyObject_StrNonNil obj
    retIfExc(objStr)
    $PyStrObject(objStr).str
  if args.len != 0:
    writeStdoutCompat args[0].toStr
    if args.len > 1:
      for i in 1..<args.len:
        writeStdoutCompat sep
        writeStdoutCompat args[i].toStr
  when noWrite:
    assert endl == NewLine
    echoCompat res
  else:
    writeStdoutCompat endl
  pyNone
registerBltinFunction("print", builtinPrint)


implBltinFunc dir(obj: PyObject):
  # why in CPython 0 argument becomes `locals()`? no idea
  # get mapping proxy first then talk about how do deal with __dict__ of type
  var res = newPyList()
  template add(k) = res.add k
  for k in obj.getTypeDict.keys(): add k
  if obj.hasDict:
    for k in (PyDictObject(obj.getDictUnsafe)).keys: add k
  res


implBltinFunc id(obj: PyObject):
  newPyInt(obj.id)

implBltinFunc len(obj: PyObject):
  obj.callMagic(len)


implBltinFunc hash(obj: PyObject): obj.callMagic(hash)

implBltinFunc iter(obj: PyObject): obj.callMagic(iter)

template callWithKeyAndMayDefault(call; tk; N) =
  checkArgNum N, N+1
  let obj = args[N-1]
  if args.len == N:
    return call obj
  let defVal = args[N]
  result = obj.call
  if result.isExceptionOf tk:
    return defVal

template genBltWithKeyAndMayDef(blt; tk; N, call){.dirty.} =
  proc `builtin blt`*(args: seq[PyObject]): PyObject {. cdecl .} =
    template callNext(obj): PyObject = call
    callWithKeyAndMayDefault callNext, tk, N
  registerBltinFunction(astToStr(blt), `builtin blt`)

genBltWithKeyAndMayDef next, StopIter, 1: obj.callMagic(iternext)
genBltWithKeyAndMayDef getattr, Attribute, 2: PyObject_GetAttr(args[0], obj)

template genBltOfNArg(blt; N, call){.dirty.} =
  proc `builtin blt`*(args: seq[PyObject]): PyObject {. cdecl .} =
    checkArgNum N
    call
  registerBltinFunction(astToStr(blt), `builtin blt`)

genBltOfNArg setattr, 3: PyObject_Setattr(args[0], args[1], args[2])
genBltOfNArg delattr, 2: PyObject_Delattr(args[0], args[1])
genBltOfNArg hasattr, 2:
  let res = PyObject_GetOptionalAttr(args[0], args[1], result)
  case res
  of Error: result
  of Get: pyTrueObj
  of Missing: pyFalseObj

implBltinFunc repr(obj: PyObject): obj.callMagic(repr)

implBltinFunc buildClass(funcObj: PyFunctionObject, name: PyStrObject), "__build_class__":
  # may fail because of wrong number of args, etc.
  let f = newPyFrame(funcObj)
  if f.isThrownException:
    unreachable("funcObj shouldn't have any arg issue")
  let retObj = f.evalFrame
  if retObj.isThrownException:
    return retObj
  tpMagic(Type, new)(@[pyTypeObjectType, name, newPyTuple(@[]), f.toPyDict()])


registerBltinObject("NotImplemented", pyNotImplemented)
registerBltinObject("Ellipsis", pyEllipsis)
registerBltinObject("None", pyNone)

registerBltinObject("bool", pyBoolObjectType)
registerBltinObject("bytearray", pyByteArrayObjectType)
registerBltinObject("bytes", pyBytesObjectType)
registerBltinObject("dict", pyDictObjectType)
registerBltinObject("enumerate", pyEnumerateObjectType)
registerBltinObject("float", pyFloatObjectType)
registerBltinObject("frozenset", pyFrozenSetObjectType)
registerBltinObject("int", pyIntObjectType)
registerBltinObject("list", pyListObjectType)
registerBltinObject("object", pyObjectType)
registerBltinObject("property", pyPropertyObjectType)
registerBltinObject("range", pyRangeObjectType)
registerBltinObject("reversed", pyReversedObjectType)
registerBltinObject("set", pySetObjectType)
registerBltinObject("str", pyStrObjectType)
registerBltinObject("slice", pySliceObjectType)
registerBltinObject("type", pyTypeObjectType)
registerBltinObject("tuple", pyTupleObjectType)
# not ready to use because no setup code is done when init new types
# registerBltinObject("staticmethod", pyStaticMethodObjectType)


macro registerErrors: untyped = 
  result = newStmtList()
  template registerTmpl(name:string, tp:PyTypeObject) = 
    registerBltinObject(name, tp)
  template reg(excpName, typeName: string){.dirty.} =
    result.add getAst(registerTmpl(excpName, ident(typeName)))
  for i in 0..int(ExceptionToken.high):
    let tok = ExceptionToken(i)
    let tokenStr = tok.getTokenName
    let excpName = tok.getBltinName
    reg excpName, "py" & tokenStr & "ErrorObjectType"
  for s in subErrs:
    reg s, "py" & s & "ObjectType"

registerErrors

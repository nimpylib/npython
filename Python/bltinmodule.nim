import strformat
{.used.}  # this module contains toplevel code, so never `importButNotUsed`
import neval
import builtindict
import ../Objects/[bundle, typeobject, methodobject, descrobject, funcobject,
  notimplementedobject, sliceobjectImpl]
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

  procNode.addPragma(ident("cdecl"))

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
proc builtinPrint*(args: seq[PyObject]): PyObject {. cdecl .} =
  for obj in args:
    let objStr = obj.callMagic(str)
    errorIfNotString(objStr, "__str__")
    echoCompat $PyStrObject(objStr).str
  pyNone
registerBltinFunction("print", builtinPrint)

implBltinFunc dir(obj: PyObject):
  # why in CPython 0 argument becomes `locals()`? no idea
  # get mapping proxy first then talk about how do deal with __dict__ of type
  var mergedDict = newPyDict()
  mergedDict.update(obj.getTypeDict)
  if obj.hasDict:
    mergedDict.update(PyDictObject(obj.getDict))
  mergedDict.keys


implBltinFunc id(obj: PyObject):
  newPyInt(obj.id)

implBltinFunc len(obj: PyObject):
  obj.callMagic(len)


implBltinFunc hash(obj: PyObject): obj.callMagic(hash)

implBltinFunc iter(obj: PyObject): obj.callMagic(iter)

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
registerBltinObject("bool", pyBoolObjectType)
registerBltinObject("Ellipsis", pyEllipsis)
registerBltinObject("None", pyNone)
registerBltinObject("type", pyTypeObjectType)
registerBltinObject("range", pyRangeObjectType)
registerBltinObject("slice", pySliceObjectType)
registerBltinObject("list", pyListObjectType)
registerBltinObject("tuple", pyTupleObjectType)
registerBltinObject("dict", pyDictObjectType)
registerBltinObject("set", pySetObjectType)
registerBltinObject("frozenset", pyFrozenSetObjectType)
registerBltinObject("int", pyIntObjectType)
registerBltinObject("str", pyStrObjectType)
registerBltinObject("property", pyPropertyObjectType)
# not ready to use because no setup code is done when init new types
# registerBltinObject("staticmethod", pyStaticMethodObjectType)


macro registerErrors: untyped = 
  result = newStmtList()
  template registerTmpl(name:string, tp:PyTypeObject) = 
    registerBltinObject(name, tp)
  for i in 1..int(ExceptionToken.high):
    let tokenStr = $ExceptionToken(i)
    let excpName = tokenStr & "Error"
    let typeName = fmt"py{tokenStr}ErrorObjectType"
    result.add getAst(registerTmpl(excpName, ident(typeName)))

registerErrors

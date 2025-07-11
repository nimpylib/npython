# the object file is devided into two parts: pyobjectBase.nim is for very basic and 
# generic pyobject behavior; pyobject.nim is for helpful macros for object method
# definition
import macros except name
import sets
import sequtils
import strformat
import strutils
import hashes
import tables

import ../Utils/[utils, macroutils]
import pyobjectBase

export macros except name
export pyobjectBase


# some helper templates for internal object magics or methods call

template getMagic*(obj: PyObject, methodName): untyped = 
  obj.pyType.magicMethods.methodName

template getFun*(obj: PyObject, methodName: untyped, handleExcp=false): untyped = 
  if obj.pyType.isNil:
    unreachable("Py type not set")
  let fun = getMagic(obj, methodName)
  if fun.isNil:
    let objTypeStr = $obj.pyType.name
    let methodStr = astToStr(methodName)
    let msg = "No " & methodStr & " method for " & objTypeStr & " defined"
    let excp = newTypeError(msg)
    when handleExcp:
      handleException(excp)
    else:
      return excp
  fun


# XXX: `obj` is used twice so it better be a simple identity
# if it's a function then the function is called twice!

# is there any ways to reduce the repetition? simple template won't work
template callMagic*(obj: PyObject, methodName: untyped, handleExcp=false): PyObject = 
  let fun = obj.getFun(methodName, handleExcp)
  let res = fun(obj)
  when handleExcp:
    if res.isThrownException:
      handleException(res)
    res
  else:
    res

  
template callMagic*(obj: PyObject, methodName: untyped, arg1: PyObject, handleExcp=false): PyObject = 
  let fun = obj.getFun(methodName, handleExcp)
  let res = fun(obj, arg1)
  when handleExcp:
    if res.isThrownException:
      handleException(res)
    res
  else:
    res

template callMagic*(obj: PyObject, methodName: untyped, 
                    arg1, arg2: PyObject, handleExcp=false): PyObject = 
  let fun = obj.getFun(methodName, handleExcp)
  let res = fun(obj, arg1, arg2)
  when handleExcp:
    if res.isThrownException:
      handleException(res)
    res
  else:
    res


# get proc name according to type (e.g. `Dict`) and method name (e.g. `repr`)
macro tpMagic*(tp, methodName: untyped): untyped = 
  ident(methodName.strVal.toLowerAscii & "Py" & tp.strVal & "ObjectMagic")

macro tpMethod*(tp, methodName: untyped): untyped = 
  ident(methodName.strVal.toLowerAscii & "Py" & tp.strVal & "ObjectMethod")

macro tpGetter*(tp, methodName: untyped): untyped = 
  ident(methodName.strVal.toLowerAscii & "Py" & tp.strVal & "ObjectGetter")

macro tpSetter*(tp, methodName: untyped): untyped = 
  ident(methodName.strVal.toLowerAscii & "Py" & tp.strVal & "ObjectSetter")

proc registerBltinMethod*(t: PyTypeObject, name: string, fun: BltinMethod) = 
  if t.bltinMethods.hasKey(name):
    unreachable(fmt"Method {name} is registered twice for type {t.name}")
  t.bltinMethods[name] = fun


# assert self type then cast
macro castSelf*(ObjectType: untyped, code: untyped): untyped = 
  let selfNoCastId = code.params[1][0]
  selfNoCastId.expectIdent "selfNoCast"
  code.body = newStmtList(
    nnkCommand.newTree(
      ident("assert"),
      nnkInfix.newTree(
        ident("of"),
        selfNoCastId,
        ObjectType
      )
    ),
    newLetStmt(
      ident("self"),
      newCall(ObjectType, selfNoCastId)
    ),
    code.body
  )
  code

let unaryMethodParams {. compileTime .} = @[
      ident("PyObject"),  # return type
      newIdentDefs(ident("selfNoCast"), ident("PyObject")),  # first arg, self
    ]

let binaryMethodParams {. compileTime .} = unaryMethodParams & @[
      newIdentDefs(ident("other"), ident("PyObject")), # second arg, other
    ]

let ternaryMethodParams {. compileTime .} = unaryMethodParams & @[
      newIdentDefs(ident("arg1"), ident("PyObject")),
      newIdentDefs(ident("arg2"), ident("PyObject")),
    ]

let bltinMethodParams {. compileTime .} = unaryMethodParams & @[
      newIdentDefs(
        ident("args"), 
        nnkBracketExpr.newTree(ident("seq"), ident("PyObject")),
        nnkPrefix.newTree( # default arg
          ident("@"),
          nnkBracket.newTree()
        )                      
      ),
    ]

# used in bltinmodule.nim
let bltinFuncParams* {. compileTime .} = @[
      ident("PyObject"),  # return type
      newIdentDefs(
        ident("args"), 
        nnkBracketExpr.newTree(ident("seq"), ident("PyObject")),
        nnkPrefix.newTree( # default arg
          ident("@"),
          nnkBracket.newTree()
        )                      
      ),
    ]

proc getParams(methodName: NimNode): seq[NimNode] = 
  var m: MagicMethods
  # the loop is no doubt slow, however we are at compile time and this won't cost
  # 1ms during the entire compile process on mordern CPU
  for name, tp in m.fieldPairs:
    if name == methodName.strVal:
      if tp is UnaryMethod:
        return unaryMethodParams
      elif tp is BinaryMethod:
        return binaryMethodParams
      elif tp is TernaryMethod:
        return ternaryMethodParams
      elif tp is BltinMethod:
        return bltinMethodParams
      elif tp is BltinFunc:
        return bltinFuncParams
      else:
        unreachable
  error(fmt"method name {methodName.strVal} is not magic method")


proc objName2tpObjName(objName: string): string {. compileTime .} = 
  result = objName & "Type"
  result[0] = result[0].toLowerAscii

# example here: For a definition like `i: PyIntObject`
# obj: i
# tp: PyIntObject like
# tpObj: pyIntObjectType like
template checkTypeTmpl(obj, tp, tpObj, methodName) = 
  # should use a more sophisticated way to judge type
  if not (obj of tp):
    let expected {. inject .} = tpObj.name
    let got {. inject .}= obj.pyType.name
    let mName {. inject .}= methodName
    let msg = fmt"{expected} is requred for {mName} (got {got})"
    return newTypeError(msg)


macro checkArgTypes*(nameAndArg, code: untyped): untyped = 
  let methodName = nameAndArg[0]
  var argTypes = nameAndArg[1]
  let body = newStmtList()
  var varargName: string
  if (argTypes.len != 0) and (argTypes[^1].kind == nnkPrefix):
    let varargs = argTypes[^1]
    assert varargs[0].strVal == "*"
    varargName = varargs[1].strVal
  let argNum = argTypes.len
  if varargName == "":
    #  return `checkArgNum(1, "append")` like
    body.add newCall(ident("checkArgNum"), 
               newIntLitNode(argNum), 
               newStrLitNode(methodName.strVal)
             )
  else:
    body.add newCall(ident("checkArgNumAtLeast"), 
               newIntLitNode(argNum - 1), 
               newStrLitNode(methodName.strVal)
             )
    let remainingArgNode = ident(varargname)
    body.add(quote do:
      let `remainingArgNode` = args[`argNum`-1..^1]
    )


  for idx, child in argTypes:
    if child.kind == nnkPrefix:
      continue
    let obj = nnkBracketExpr.newTree(
      ident("args"),
      newIntLitNode(idx),
    )
    let name = child[0]
    let tp = child[1]
    if tp.strVal == "PyObject":  # won't bother checking 
      body.add(quote do:
          let `name` = `obj`
      )
    else:
      let tpObj = ident(objName2tpObjName(tp.strVal))
      let methodNameStrNode = newStrLitNode(methodName.strVal)
      body.add(getAst(checkTypeTmpl(obj, tp, tpObj, methodNameStrNode)))
      body.add(quote do:
        let `name` = `tp`(`obj`)
      )
  body.add(code.body)
  code.body = body
  code


# works with thingks like `append(obj: PyObject)`
# if no parenthesis, then return nil as argTypes, means do not check arg type
proc getNameAndArgTypes*(prototype: NimNode): (NimNode, NimNode) = 
  if prototype.kind == nnkIdent or prototype.kind == nnkSym:
    return (prototype, nil)
  let argTypes = nnkPar.newTree()
  let methodName = prototype[0]
  if prototype.kind == nnkObjConstr:
    for i in 1..<prototype.len:
      argTypes.add prototype[i]
  elif prototype.kind == nnkCall: # `clear()` for no arg case
    discard # empty arg list
  elif prototype.kind == nnkPrefix:
    error("got prefix prototype, forget to declare object as mutable?")
  else:
    error("got prototype: " & prototype.treeRepr)

  (methodName, argTypes)

# kinds of methods for python objects.
type
  MethodKind {. pure .} = enum
    Common,
    Magic,
    Getter,
    Setter

proc implMethod*(prototype, ObjectType, pragmas, body: NimNode, kind: MethodKind): NimNode = 
  # transforms user implementation code
  # prototype: function defination, contains argumetns to check
  # ObjectType: the code belongs to which object
  # pragmas: custom pragmas
  # body: function body
  var (methodName, argTypes) = getNameAndArgTypes(prototype)
  methodName.expectKind({nnkIdent, nnkSym})
  ObjectType.expectKind(nnkIdent)
  body.expectKind(nnkStmtList)
  pragmas.expectKind(nnkBracket)
  var tail: string
  case kind
  of MethodKind.Common:
    tail = "Method"
  of MethodKind.Magic:
    tail = "Magic"
  of MethodKind.Getter:
    tail = "Getter"
  of MethodKind.Setter:
    tail = "Setter"
  # use `toLowerAscii` because we used uppercase in declaration to prevent conflict with
  # Nim keywords. Now it's not necessary as we append lots of things
  # implListMagic str = strPyListObjectMagic
  # implListMethod append = appendPyListObjectMethod
  # use tpMagic and tpMethod to build the name for internal use
  let name = ident(($methodName).toLowerAscii & $ObjectType & tail)
  var typeObjName = objName2tpObjName($ObjectType)
  let typeObjNode = ident(typeObjName)

  var params: seq[NimNode]
  case kind
  of MethodKind.Common:
    params = bltinMethodParams
  of MethodKind.Magic:
    params = getParams(methodName)
  of MethodKind.Getter:
    params = unaryMethodParams
  of MethodKind.Setter:
    params = binaryMethodParams

  let procNode = newProc(
    nnkPostFix.newTree(
      ident("*"),  # let other modules call without having to lookup in the type dict
      name,
    ),
    params.deepCopy,
    body, # the function body
  )
  # add pragmas, the last to add is the first to execute
  
  # custom pragms
  for p in pragmas:
    procNode.addPragma(p)

  # builtin function has no `self` to cast
  if params != bltinFuncParams:
    procNode.addPragma(
      nnkExprColonExpr.newTree(
        ident("castSelf"),
        ObjectType
      )
    )

  # no arg type info is provided
  if not argTypes.isNil:
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

  result = newStmtList()
  result.add procNode

  case kind
  of MethodKind.Common:
    result.add nnkCall.newTree(
        nnkDotExpr.newTree(
          typeObjNode,
          newIdentNode("registerBltinMethod")
        ),
        newLit(methodName.strVal),
        name
      )
  of MethodKind.Magic:
    result.add newAssignment(
        newDotExpr(
          newDotExpr(
            ident(typeObjName),
            ident("magicMethods")
          ),
          methodName
        ),
        name
      )
  else: # registered manually
    discard


macro reprLock*(code: untyped): untyped = 
  let reprEnter = quote do:
    if self.reprLock:
      return newPyString("...")
    self.reprLock = true

  let reprLeave = quote do: 
    self.reprLock = false

  code.body = newStmtList( 
      reprEnter,
      nnkTryStmt.newTree(
        code.body,
        nnkFinally.newTree(
          nnkStmtList.newTree(
            reprLeave
          )
        )
      )
    )
  code


macro mutable*(kind, code: untyped): untyped = 
  if kind.strVal != "read" and kind.strVal != "write":
    error("got mutable pragma arg: " & kind.strVal)
  var enterNode, leaveNode: NimNode
  if kind.strVal == "write":
    enterNode = quote do:
      if 0 < self.readNum or self.writeLock:
        let msg = "Write failed because object is been read or written."
        return newLockError(msg)
      self.writeLock = true
    leaveNode = quote do:
        self.writeLock = false
  else:
    enterNode = quote do:
      if self.writeLock:
        let msg = "Read failed because object is been written."
        return newLockError(msg)
      inc self.readNum
    leaveNode = quote do:
      dec self.readNum
  code.body = nnkStmtList.newTree(
                enterNode,
                nnkTryStmt.newTree(
                  code.body,
                  nnkFinally.newTree(
                    nnkStmtList.newTree(
                      leaveNode
                    )
                  )
                )
              )
  code

# generate useful macros for function defination
template methodMacroTmpl(name: untyped, nameStr: string) = 
  const objNameStr = "Py" & nameStr & "Object"

  # default args won't work here, so use overloading
  macro `impl name Magic`(methodName, pragmas, code:untyped): untyped {. used .} = 
    implMethod(methodName, ident(objNameStr), pragmas, code, MethodKind.Magic)

  macro `impl name Magic`(methodName, code:untyped): untyped {. used .} = 
    getAst(`impl name Magic`(methodName, nnkBracket.newTree(), code))

  macro `impl name Method`(prototype, pragmas, code:untyped): untyped {. used .}= 
    implMethod(prototype, ident(objNameStr), pragmas, code, MethodKind.Common)

  macro `impl name Method`(prototype, code:untyped): untyped {. used .}= 
    getAst(`impl name Method`(prototype, nnkBracket.newTree(), code))

  macro `impl name Getter`(prototype, pragmas, code:untyped): untyped {. used .}= 
    implMethod(prototype, ident(objNameStr), pragmas, code, MethodKind.Getter)

  macro `impl name Getter`(prototype, code:untyped): untyped {. used .}= 
    getAst(`impl name Getter`(prototype, nnkBracket.newTree(), code))

  macro `impl name Setter`(prototype, pragmas, code:untyped): untyped {. used .}= 
    implMethod(prototype, ident(objNameStr), pragmas, code, MethodKind.Setter)

  macro `impl name Setter`(prototype, code:untyped): untyped {. used .}= 
    getAst(`impl name Setter`(prototype, nnkBracket.newTree(), code))

# further reduce number of required args
macro methodMacroTmpl*(name: untyped): untyped = 
  getAst(methodMacroTmpl(name, name.strVal))

macro declarePyType*(prototype, fields: untyped): untyped = 
  prototype.expectKind(nnkCall)
  fields.expectKind(nnkStmtList)
  var tpToken, mutable, dict, reprLock: bool
  var baseTypeStr = "PyObject"
  # parse options the silly way
  for i in 1..<prototype.len:
    let option = prototype[i]
    if option.kind == nnkCall:
      assert option[0].strVal == "base"
      baseTypeStr = "Py" & option[1].strVal & "Object"
      continue
    option.expectKind(nnkIdent)
    let property = option.strVal
    if property == "tpToken":
      tpToken = true
    elif property == "mutable":
      mutable = true
    elif property == "dict":
      dict = true
    elif property == "reprLock":
      reprLock = true
    else:
      error("unexpected property: " & property)
  if (baseTypeStr == "PyObject") and dict:
    baseTypeStr &= "WithDict"

  let nameIdent = prototype[0]
  let fullNameIdent = ident("Py" & nameIdent.strVal & "Object")

  result = newStmtList()
  if dict:
    result.add nnkImportStmt.newTree(ident("dictobject"))
  # the fields are not recognized as type attribute declaration
  # need to cast here, but can not handle object variants
  var reclist = nnkRecList.newTree()
  proc addField(recList, name, tp: NimNode)=
    let newField = nnkIdentDefs.newTree(
      nnkPostFix.newTree(
        ident("*"),
        name
      ),
      tp,
      newEmptyNode()
    )  
    recList.add(newField)

  for field in fields.children:
    if field.kind == nnkDiscardStmt:
      continue
    field.expectKind(nnkCall)
    reclist.addField(field[0], field[1][0])

  # add fields related to options
  if reprLock:
    reclist.addField(ident("reprLock"), ident("bool"))
  if mutable:
    reclist.addField(ident("readNum"), ident("int"))
    reclist.addField(ident("writeLock"), ident("bool"))

  # declare the type
  let decObjNode = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostFix.newTree(
        ident("*"),
        fullNameIdent,
      ),
      newEmptyNode(),
      nnkRefTy.newTree(
        nnkObjectTy.newTree(
          newEmptyNode(),
          nnkOfInherit.newTree(
            ident(baseTypeStr)
          ),
          recList
        )
      )
    )
  )
  result.add(decObjNode)

  # boilerplates for pyobject type
  template initTypeTmpl(name, nameStr, hasTpToken, hasDict) = 
    let `py name ObjectType`* {. inject .} = newPyType(nameStr)

    when hasTpToken:
      `py name ObjectType`.kind = PyTypeToken.`name`
      proc `ofPy name Object`*(obj: PyObject): bool {. cdecl, inline .} = 
        obj.pyType.kind == PyTypeToken.`name`

    # base constructor that should be used for any custom constructors except for 
    # code objects which require finalizers. 
    # make it public so that impl files can also use
    proc `newPy name Simple`*: `Py name Object` {. cdecl .}= 
      # use `result` here seems to be buggy
      let obj = new `Py name Object`
      obj.pyType = `py name ObjectType`
      when defined(js):
        obj.giveId
      when hasDict:
        obj.dict = newPyDict()
      obj

    # using function argument as a finalizer is buggy in nim 0.19.0,
    # so use a template as workaround, gh-10376
    template `newPy name Finalizer`*(
                              obj: var `Py name Object`,
                              finalizer: proc (x: `Py name Object`) {. nimcall .}) = 
      new(obj, finalizer)
      obj.pyType = `py name ObjectType`
      when hasDict:
        obj.dict = newPyDict()


    # default for __new__ hook, could be overrided at any time
    proc `newPy name Default`(args: seq[PyObject]): PyObject {. cdecl .} = 
      `newPy name Simple`()
    `py name ObjectType`.magicMethods.New = `newPy name Default`

  result.add(getAst(initTypeTmpl(nameIdent, 
    nameIdent.strVal, 
    newLit(tpToken), 
    newLit(dict)
    )))

  result.add(getAst(methodMacroTmpl(nameIdent)))

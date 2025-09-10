# the object file is devided into two parts: pyobjectBase.nim is for very basic and 
# generic pyobject behavior; pyobject.nim is for helpful macros for object method
# definition
import macros except name
import sets

import strformat
import strutils
import hashes
import tables

import ../Utils/[utils, macroutils]
import ../Include/cpython/critical_section
import ../Include/descrobject
import pyobjectBase

export macros except name
export pyobjectBase


# some helper templates for internal object magics or methods call

template getMagic*(obj: PyObject, methodName): untyped = 
  obj.pyType.magicMethods.methodName


template checkTypeNotNil(obj) =
  when not defined(release):
    if obj.pyType.isNil:
      unreachable("Py type not set")

template handleNilFunOfGetFun(obj, methodName, handleExcp) =
    let objTypeStr = $obj.pyType.name
    let methodStr = astToStr(methodName)
    let msg = "No " & methodStr & " method for " & objTypeStr & " defined"
    let excp = newTypeError(newPyStr msg)
    when handleExcp:
      handleException(excp)
    else:
      return excp

template getFun*(obj: PyObject, methodName: untyped, handleExcp=false): untyped = 
  bind checkTypeNotNil, handleNilFunOfGetFun
  obj.checkTypeNotNil
  let fun = getMagic(obj, methodName)
  if fun.isNil:
    handleNilFunOfGetFun(obj, methodName, handleExcp)
  fun


# XXX: `obj` is used twice so it better be a simple identity
# if it's a function then the function is called twice!

template checkExcAndRet[T](res: T, handleExcp): T =
  when handleExcp:
    if res.isThrownException:
      handleException(res)
    res
  else:
    res

# is there any ways to reduce the repetition? simple template won't work
template callMagic*(obj: PyObject, methodName: untyped, handleExcp=false): PyObject = 
  let fun = obj.getFun(methodName, handleExcp)
  let res = fun(obj)
  bind checkExcAndRet
  res.checkExcAndRet handleExcp

  
template callMagic*(obj: PyObject, methodName: untyped, arg1: PyObject, handleExcp=false): PyObject = 
  let fun = obj.getFun(methodName, handleExcp)
  let res = fun(obj, arg1)
  bind checkExcAndRet
  res.checkExcAndRet handleExcp


template callInplaceMagic*(obj: PyObject, methodName1: untyped,
    arg1: PyObject, handleExcp=false): PyObject = 
  bind checkTypeNotNil, handleNilFunOfGetFun
  bind checkExcAndRet
  obj.checkTypeNotNil
  var fun = obj.getMagic(methodName1)
  if fun.isNil:
    pyNotImplemented
  else:
    if fun.isNil:
      handleNilFunOfGetFun(obj, methodName1, handleExcp)
    else:
      let res = fun(obj, arg1)
      res.checkExcAndRet handleExcp

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

template checkTypeTmplImpl(obj: PyObject{atom}, tp, tpObjName; msgInner="") {.dirty.} = 
  # should use a more sophisticated way to judge type
  if not (obj of tp):
    let expected = tpObjName
    let got = obj.typeName
    let tmsgInner = msgInner
    let msg = fmt"{expected} is requred{tmsgInner} (got {got})"
    return newTypeError newPyStr(msg)
template checkTypeTmplImpl(obj: PyObject, tp, tpObjName; msgInner="") = 
  bind checkTypeTmplImpl
  let tobj = obj
  checkTypeTmplImpl(tobj, tp, tpObjName, msgInner)

template checkTypeTmpl(obj, tp, tpObj, methodName) =
  checkTypeTmplImpl(obj, tp, tpObj.name, " for" & methodName)

template checkTypeOrRetTE*(obj, tp; tpObj: PyTypeObject; methodName: string) =
  ## example here: For a definition like `i: PyIntObject`
  ## obj: i
  ## tp: PyIntObject like
  ## tpObj: pyIntObjectType like
  bind checkTypeTmpl
  checkTypeTmpl obj, tp, tpObj, methodName

template checkTypeOrRetTE*(obj, tp; tpObj: PyTypeObject) =
  bind checkTypeTmpl
  checkTypeTmplImpl obj, tp, tpObj.name

macro toTypeObject*[O: PyObject](tp: typedesc[O]): PyTypeObject =
  ident ($tp).toLowerAscii & "Type"

template checkTypeOrRetTE*(obj, tp) =
  bind toTypeObject
  checkTypeOrRetTE obj, tp, toTypeObject(tp)

macro call2AndMoreArg(callee, arg1, arg2, more): untyped =
  result = newCall(callee, arg1, arg2)
  for i in more: result.add i

template castTypeOrRetTE*[O: PyObject](obj: PyObject, tp: typedesc[O]; extraArgs: varargs[untyped]): O =
  call2AndMoreArg(checkTypeOrRetTE, obj, tp, extraArgs)
  cast[tp](obj)

proc isSeqObject(n: NimNode): bool =
  n.kind == nnkBracketExpr and n[0].eqIdent"seq" and n[1].eqIdent"PyObject"

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
  let oriParams = code.params
  let multiArg = argNum > 1 or oriParams[^1][1].isSeqObject
  if multiArg:
    if varargName == "":
      #  return `checkArgNum(1, "append")` like
      body.add newCall(ident("checkArgNum"), 
                newIntLitNode(argNum), 
                newStrLitNode($methodName)
              )
    else:
      body.add newCall(ident("checkArgNumAtLeast"), 
                newIntLitNode(argNum - 1), 
                newStrLitNode($methodName)
              )
      let remainingArgNode = ident(varargname)
      body.add(quote do:
        let `remainingArgNode` = args[`argNum`-1..^1]
      )

  for idx, child in argTypes:
    if child.kind == nnkPrefix:
      continue
    let obj = if multiArg: nnkBracketExpr.newTree(
      ident("args"),
      newIntLitNode(idx),
    ) else: oriParams[idx+2][0]
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

const atomAllowAsImplHead = {nnkIdent, nnkSym, nnkStrLit}

# works with thingks like `append(obj: PyObject)`
# if no parenthesis, then return nil as argTypes, means do not check arg type
proc getNameAndArgTypes*(prototype: NimNode): (NimNode, NimNode) = 
  var prototype = prototype
  if prototype.kind == nnkOpenSymChoice:
    prototype = prototype[0]  # we only care its strVal, so pick from any
  if prototype.kind in atomAllowAsImplHead:
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

proc toIdentStr(s: string): string =
  ## "__xx__" -> "DUxxDU", "xXx" -> "xxx"
  ##   as Nim disallow ident starts or ends with underscore
  const
    DU = "DU"
    SU = "SU"
  template addDU = result.add DU
  template addSU = result.add SU
  var
    lo = 0
    hi = s.high
  
  # handle start
  case s
  of "_": addSU; return
  of "__": addDU; return
  elif s.startsWith"__":
    addDU
    lo.inc 2
  elif s[0] == '_':
    addSU
    lo.inc
  else: discard

  # handle end
  var ends = ""
  if s.endsWith"__":
    ends = DU
    hi.dec 2
  elif s[hi] == '_':
    ends = SU
    hi.dec
  result.add s.toOpenArray(lo, hi).toLower
  result.add ends

proc toIdentStr(n: NimNode): string =
  if n.kind == nnkStrLit:
    n.strVal.toIdentStr
  else: # shall be valid already
    ($n).toLowerAscii

proc implMethod*(prototype, ObjectType, pragmas, body: NimNode, kind: MethodKind): NimNode = 
  # transforms user implementation code
  # prototype: function defination, contains argumetns to check
  # ObjectType: the code belongs to which object
  # pragmas: custom pragmas
  # body: function body
  var (methodName, argTypes) = getNameAndArgTypes(prototype)
  if methodName.kind == nnkAccQuoted:  # for reversed keyword
    var ls = methodName
    var name = "" 
    for i in ls:
      name.add i.strVal
    methodName = ident name
  methodName.expectKind({nnkClosedSymChoice}+atomAllowAsImplHead)
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
  let methodNimNameStr = methodName.toIdentStr
  let name = ident(methodNimNameStr & $ObjectType & tail)
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
  procNode.addPragma(bindSym("pyCFuncPragma"))

  result = newStmtList()
  result.add procNode

  case kind
  of MethodKind.Common:
    result.add nnkCall.newTree(
        nnkDotExpr.newTree(
          typeObjNode,
          newIdentNode("registerBltinMethod")
        ),
        newLit($methodName),
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


proc reprLockImpl(s, code: NimNode): NimNode =
  let reprEnter = quote do:
    if self.reprLock:
      return newPyAscii(`s`)
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

macro reprLockWithMsg*(s: string, code: untyped): untyped =
  reprLockImpl(s, code)

macro reprLock*(code: untyped): untyped = 
  reprLockImpl(newLit"...", code)

template allowSelfReadWhenBeforeRealWrite*(body) =
  self.writeLock = false
  body
  self.writeLock = true

macro mutable*(kind, code: untyped): untyped = 
  if kind.strVal != "read" and kind.strVal != "write":
    error("got mutable pragma arg: " & kind.strVal)
  let selfId = ident"self"
  if kind.strVal == "write":
    code.body = getAst(criticalWrite(selfId, code.body))
  else:
    code.body = getAst(criticalRead(selfId, code.body))
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
  ## `prototype` is of nnkCall format,
  ##   whose arguments call contains:
  ##   - base: BASE
  ##   - typeName: TYPE_NAME;
  ##     TYPE_NAME defaults to lowerAscii of `prototype[0]`
  ##   - tpToken, dict, mutable, reprLock
  prototype.expectKind(nnkCall)
  fields.expectKind(nnkStmtList)
  var tpToken, mutable, dict, reprLock: bool
  var baseStr = ""
  var typeName: string
  # parse options the silly way
  for i in 1..<prototype.len:
    let option = prototype[i]
    if option.kind == nnkCall:
      case option[0].strVal
      of "base":
        baseStr = option[1].strVal
        continue
      of "typeName":
        typeName = option[1].strVal
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

  var baseTypeStr ="Py" & baseStr & "Object"
  let baseTypeObjStr = "py" & baseStr & "ObjectType"
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
  proc addField(recList, name, tp: NimNode, fieldPrivate=false)=
    let fid = if fieldPrivate: name else: name.postfix"*"
    let newField = nnkIdentDefs.newTree(fid, tp, newEmptyNode())  
    recList.add(newField)
  let pyObjType = ident "py" & nameIdent.strVal & "ObjectType"

  var members = newNimNode nnkBracket

  for field in fields.children:
    if field.kind == nnkDiscardStmt:
      continue
    field.expectKind(nnkCall)
    var name = field[0]
    let fieldType = field[1][0]
    var fieldPrivate = false #XXX: historial
    if name.kind == nnkPragmaExpr:
      let pragmas = name[1]
      name = name[0]
      pragmas.expectKind nnkPragma

      var memberPyId: NimNode
      for i in pragmas:
        if i.eqIdent"member" or i.kind == nnkCall and i[0].eqIdent"member":
          var memberPragma = i
          if memberPragma.kind == nnkCall:
            expectLen memberPragma, 2
            memberPyId = memberPragma[1]
            memberPyId.expectKind {nnkStrLit, nnkRStrLit, nnkTripleStrLit}
            memberPragma = memberPragma[0]
            memberPragma.expectIdent"member"
          else:
            memberPyId = name
        elif i.kind == nnkIdent:
          case i.strVal
          of "dunder_member":
            memberPyId = ident("__" & name.strVal & "__")
          of "private": fieldPrivate = true
      
      if memberPyId != default NimNode:
        var flags = newCall(bindSym"pyMemberDefFlagsFromTags")
        for i in 1..<pragmas.len:
          let tag = pragmas[i]
          tag.expectKind nnkIdent
          flags.add tag
        members.add newCall(bindSym"initPyMemberDef",
          newStrLitNode memberPyId.strVal,
          newCall("typeof", fieldType), # NIM-BUG: avoid not being regarded as typedesc
          newCall(bindSym"offsetOf", fullNameIdent, name),
          nnkExprEqExpr.newTree(ident("flags"), flags)
        )
    reclist.addField(name, fieldType, fieldPrivate)

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
  template initTypeTmpl(tbase, pyObjType, fullNameIdent, name, nameStr, hasTpToken, hasDict) = 
    let `pyObjType`* {. inject .} = newPyType[`fullNameIdent`](nameStr, tbase)

    proc `ofExactPy name Object`*(obj: PyObject): bool {. cdecl, inline .} = 
      isType(obj.pyType, `pyObjType`)
    when hasTpToken:
      `pyObjType`.kind = PyTypeToken.`name`
      proc `ofPy name Object`*(obj: PyObject): bool {. cdecl, inline .} = 
        obj.pyType.kind == PyTypeToken.`name`
    else:
      proc `ofPy name Object`*(obj: PyObject): bool {. cdecl, inline .} = 
        #TODO:tp_bases
        var cur: PyTypeObject = obj.pyType
        while not cur.isNil:
          if isType(cur, `pyObjType`): return true
          cur = cur.base
        return false

    proc `newPy name Simple`*: `Py name Object` {. cdecl .}= 
      # use `result` here seems to be buggy
      let obj = `Py name Object` `pyObjType`.tp_alloc(`pyObjType`, 0)
      when defined(js):
        obj.giveId
      when hasDict:
        obj.dict = newPyDict()
      obj

    # default for __new__ hook, could be overrided at any time
    proc `newPy name Default`(args: seq[PyObject]): PyObject {. cdecl .} = 
      `newPy name Simple`()
    `pyObjType`.magicMethods.New = `newPy name Default`

  if typeName == "":
    typeName = nameIdent.strVal.toLowerAscii
  result.add(getAst(initTypeTmpl(ident(baseTypeObjStr), pyObjType, fullNameIdent, nameIdent,
    typeName, 
    newLit(tpToken), 
    newLit(dict)
    )))

  if members.len > 0:
    let mem_asgn = newAssignment(
      pyObjType.newDotExpr(ident"members"),
      newCall(bindSym"initRtArray", members)
    )
    result.add mem_asgn

  result.add(getAst(methodMacroTmpl(nameIdent)))

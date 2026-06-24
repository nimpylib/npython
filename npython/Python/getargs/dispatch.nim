
import std/macros
import ./[
  tovalUtils,
  va_and_kw,
  tovals,
  topys,
]
export tovals, topys
import ../../Objects/[
  pyobject,
  dictobject,
  exceptions,
  noneobject,
]
import ../../Objects/exceptions/oserr/convert


proc auditArgsEmpty(auditArgs: NimNode): bool =
  auditArgs.kind == nnkNilLit

proc addAuditCall(body: NimNode; eventName: string; auditArgs: NimNode) =
  if auditArgs.auditArgsEmpty:
    return
  let call = newCall(ident"audit", newLit(eventName))
  for arg in auditArgs:
    call.add arg
  body.add quote do:
    retIfExc `call`

proc clinicGenAuxHelper(hasSelfParam, passSelfToOrigin: bool,
    genedPureNameStr: string, def: NimNode, exported=true,
    inferResult=false, auditArgs = newNilLit(),
    auditEvent = genedPureNameStr): tuple[name, params, body: NimNode] =
  let
    originFuncName = def.name
    pureName = ident genedPureNameStr
    name = if exported: # exported
      pureName.postfix"*"
    else: pureName

  let params = def.params
  var vargs = newNimNode nnkBracket
  var beginKwOnly = false
  var kwOnlyList: seq[string]

  var callOriArgs: seq[NimNode]
  let resType = params[0]
  let noRes = resType.kind == nnkEmpty
  var start = 1
  if passSelfToOrigin: start = 2

  for i in start..<params.len:
    let
      pDef = params[i]
      oldPName = pDef[0].getNameOfParam
      pName = freshIdentLike oldPName
    assert pDef.len == 3, "#TODO:clinic current each param match one type (e.g. `a, b: int` shall be written as `a: int, b: int`)"
    callOriArgs.add pName
    if beginKwOnly:
      kwOnlyList.add pName.strVal
    elif pDef[0].isKwOnlyStartImpl:
      beginKwOnly = true
      kwOnlyList.add pName.strVal
    vargs.add pDef
  let
    nparam_args = ident"args"
    nparam_kwargs = ident"kwargs"
  let parserCall = PyArg_VaParseTupleAndKeywordsAs(newStrLitNode genedPureNameStr, nparam_args, nparam_kwargs, kwOnlyList, vargs)
  let PyObjT = bindSym"PyObject"
  let nparams = nnkFormalParams.newTree(PyObjT)
  if hasSelfParam:
    let self = ident"self"
    nparams.add newIdentDefs(self, PyObjT)
    if passSelfToOrigin:
      callOriArgs.insert self, 0

  nparams.add newIdentDefs(nparam_args, nnkBracketExpr.newTree(bindSym"openArray", PyObjT))
  nparams.add newIdentDefs(nparam_kwargs, PyObjT)
  let callOrigin = originFuncName.newCall callOriArgs
  var body = newStmtList()
  body.add quote do:
    let `nparam_kwargs` = PyDictObject `nparam_kwargs`
    retIfExc `parserCall`
  body.addAuditCall(auditEvent, auditArgs)
  if inferResult:
    let cvt = quote do:
      let res = `callOrigin`
      retIfExc toPy(res, result)
    body.add quote do:
      when compiles(`cvt`):
        `cvt`
      else:
        `callOrigin`
        result = pyNone
  elif noRes:
    body.add quote do:
      `callOrigin`
      result = pyNone
  else:
    body.add quote do:
      `callOrigin`
    body = quote do:
      let res = `body`
      let exc = toPy(res, result)
      retIfExc exc
  (name, nparams, body)

proc newPyCProc(name, nparams, body: NimNode, pragma: NimNode): NimNode =
  let emptyn = newEmptyNode()
  let nproc = nnkProcDef.newTree(name, emptyn, emptyn, nparams, pragma, emptyn, body)
  nproc

proc clinicGenAux*(hasSelf: bool, genedPureNameStr: string, def: NimNode, exported=true): NimNode =
  let (name, nparams, body) = clinicGenAuxHelper(hasSelf, hasSelf,
    genedPureNameStr, def, exported)
  let nproc = newPyCProc(name, nparams, body, nnkPragma.newTree bindSym"pyCFuncPragma")
  result = newStmtList(def, nproc)

proc clinicGenImplWithPrefix*(prefix: string, def: NimNode): NimNode =
  let
    originFuncName = def.name
    genedPureNameStr = prefix & originFuncName.strVal
    exported = def[0].kind == nnkPostfix
  if exported:
    assert def[0][0].strVal == "*"
  clinicGenAux(false, genedPureNameStr, def, exported)


macro clinicGenWithPrefix*(prefix: static[string], def) =
  clinicGenImplWithPrefix(prefix, def)

macro clinicGen*(name; exported: static[bool], def) =
  ## pragma for proc def.
  ## 
  ## Named after CPython's clinic
  ##
  ## main part of exportnpy, just before registering into module dict
  clinicGenAux(false, name.strVal, def, exported)
macro clinicGenMeth*(name; exported: static[bool], def) =
  clinicGenAux(true, name.strVal, def, exported)

macro bltin_clinicGen*(def) = clinicGenImplWithPrefix("builtin_", def)

proc genExcepts(excepts, body: NimNode): NimNode =
  ## helper for `clinicGenMethodOfKind` to generate exception sequence
  if excepts.len == 0:
    return body
  result = nnkTryStmt.newTree body
  var hasOSError = false

  for exc in excepts:
    if exc.eqIdent "OSError":
      hasOSError = true
      continue
    let alias = ident "e"
    let newPyE = ident("new" & exc.strVal)
    result.add nnkExceptBranch.newTree(
      infix(exc, "as", alias),
      quote do:
        return `newPyE`(newPyStr `alias`.msg)
    )
  if hasOSError:
    if excepts.len == 1:
      result = body
    let handleOsErrRetPyObjId = bindSym"handleOsErrRetPyObj"
    result = quote do:
      `handleOsErrRetPyObjId`: `result`
  else:
    result = newStmtList(result)

const PrcNameAsAuditEvent = ""
func isDefAuditEventName(s: string): bool = s.len == 0

proc clinicGenMethodOfKindImpl*(typ: NimNode; kind: NPyMethodKind, exceptions,
    prc: NimNode, classmethod=false, includeOriginal=true,
    passSelfToOrigin=true, inferResult=false,
    auditArgs = newNilLit(), auditEvent = PrcNameAsAuditEvent): NimNode =
  ## used for generating method with argument clinic, e.g. `PyDict_GetItem`
  ##  the method body is generated by `prc`, which is a proc that returns a NimNode
  ##  the proc takes the method name as argument, so that it can generate different body
  ##  for different methods, e.g. `PyDict_GetItem` and `PyDict_SetItem` has different body
  let hasSelfParam = kind == NPyMethodKind.Common
  result =
    if includeOriginal: newStmtList(prc)
    else: newStmtList()
  var pname = prc.name
  let exported = pname.kind == nnkPostfix
  if exported:
    assert pname[0].eqIdent"*"
    pname = pname[1]
  let genedPureNameStr = pname.strVal
  #let prc_params = prc.params
  #let args = prc_params.copyNimNode
  let (methodName, args, body) = clinicGenAuxHelper(hasSelfParam,
    hasSelfParam and passSelfToOrigin and not classmethod,
    genedPureNameStr, prc, exported,
    inferResult=inferResult, auditArgs=auditArgs,
    auditEvent=if auditEvent.isDefAuditEventName: genedPureNameStr else: auditEvent)

  #[
  let call = newCall methodName
  for i in 1..<prc_params.len:
    let e = prc_params[i]
    if kind == NPyMethodKind.Common:
      if i != 1:
        args.add e
      # skip self
    else:
      args.add e

    for i in 0..<e.len-2:
      call.add e[i]
  let resType = prc.params[0]
  ]#

  let resBody = genExcepts(exceptions, body)
  let prc_pragma = prc.pragma
  let pragmas = if prc_pragma.kind == nnkEmpty: newNimNode nnkPragma else: prc_pragma.copyNimTree

  let typS = typ.strVal
  let pytyp = ident("Py" & typS & "Object")
  let pytypObj = ident("py" & typS & "ObjectType")
  if hasSelfParam:
    args[1][0] = ident"selfNoCast"
  pragmas.add bindSym"pyCFuncPragma"
  if hasSelfParam and passSelfToOrigin and not classmethod:
    pragmas.add nnkExprColonExpr.newTree(bindSym"castSelf", pytyp)

  let methId = genSym(nskProc, methodName.strVal)
  let nproc = newPyCProc(methId, args, resbody, pragmas)
  result.add nproc

  result.addRegisterMethod(pytypObj, methodName, methId, classmethod=classmethod, kind=kind)

proc clinicGenStaticMethodOfKindImpl*(typ: NimNode; kind: NPyMethodKind,
    exceptions, prc: NimNode, auditArgs = newNilLit(),
    auditEvent = PrcNameAsAuditEvent): NimNode =
  clinicGenMethodOfKindImpl(typ, kind, exceptions, prc,
    classmethod=false, includeOriginal=false,
    passSelfToOrigin=false, inferResult=true,
    auditArgs=auditArgs, auditEvent=auditEvent)

macro clinicGenMethodOfKind*(typ; kind: static[NPyMethodKind] = NPyMethodKind.Common, exceptions: untyped = []; prc) =
  clinicGenMethodOfKindImpl(typ, kind, exceptions, prc)

macro clinicGenMethod*(typ; prc) =
  clinicGenMethodOfKindImpl(typ, NPyMethodKind.Common, nnkBracket.newNimNode, prc)

macro clinicGenMethodRaises*(typ; exceptions; prc) =
  clinicGenMethodOfKindImpl(typ, NPyMethodKind.Common, exceptions, prc)

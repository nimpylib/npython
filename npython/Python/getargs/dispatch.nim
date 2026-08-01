
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

type
  ClinicGenConf = object
    auditEvent*: string
    auditArgs*: NimNode
    postdo*: NimNode

proc ccconf*(auditEvent: string;
    auditArgs: NimNode = newNilLit();
    postdo: NimNode = newStmtList()): ClinicGenConf =
  result.auditEvent = auditEvent
  result.auditArgs = auditArgs
  result.postdo = postdo

const PrcNameAsAuditEvent = ""
func isDefAuditEventName(s: string): bool = s.len == 0

using conf: ClinicGenConf
proc replaceAuditEvent*(conf; auditEvent: string): ClinicGenConf =
  ## if in Python, it will be `conf.replace(auditEvent = auditEvent)`
  result = conf
  result.auditEvent = auditEvent

proc auditArgsEmpty(auditArgs: NimNode): bool =
  auditArgs.kind == nnkNilLit

proc splitParamDef(pDef: NimNode): seq[NimNode] =
  if pDef.kind != nnkIdentDefs or pDef.len == 3:
    return @[pDef]

  for i in 0..<pDef.len - 2:
    result.add newIdentDefs(pDef[i], pDef[^2], pDef[^1])

proc addAuditCall(body: NimNode; conf) =
  if conf.auditArgs.auditArgsEmpty:
    return
  let call = newCall(ident"audit", newLit(conf.auditEvent))
  for arg in conf.auditArgs:
    call.add arg
  body.add quote do:
    retIfExc `call`

proc clinicGenAuxHelper(hasSelfParam, passSelfToOrigin: bool,
    genedPureNameStr: string, def: NimNode, exported=true,
    conf = ccconf genedPureNameStr): tuple[name, params, body: NimNode] =
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
    for pDef in params[i].splitParamDef:
      let
        oldPName = pDef[0].getNameOfParam
        pName = freshIdentLike oldPName
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
  body.addAuditCall(conf)
  let postdo = conf.postdo
  if noRes:
    body.add quote do:
      `callOrigin`
      `postdo`
      result = pyNone
  else:
    body.add quote do:
      `callOrigin`
    body = quote do:
      let res: `resType` = `body`
      let exc = toPy(res, result)
      `postdo`
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


proc clinicGenMethodOfKindImpl*(typ: NimNode; kind: NPyMethodKind, exceptions,
    prc: NimNode, classmethod=false, includeOriginal=true,
    passSelfToOrigin=true,
    conf = ccconf PrcNameAsAuditEvent): NimNode =
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
    conf=conf.replaceAuditEvent(
        if conf.auditEvent.isDefAuditEventName: genedPureNameStr
        else: conf.auditEvent,
    )
  )

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
    exceptions, prc: NimNode, conf = ccconf PrcNameAsAuditEvent, includeOriginal=false): NimNode =
  clinicGenMethodOfKindImpl(typ, kind, exceptions, prc,
    classmethod=false, includeOriginal=includeOriginal,
    passSelfToOrigin=false,
    conf=conf)

template emptyB: NimNode = nnkBracket.newNimNode
macro clinicGenStaticMethod*(typ; prc) =
  ## Also used for define function of module
  clinicGenStaticMethodOfKindImpl(typ, Common, emptyB, prc, includeOriginal=true)
macro clinicGenStaticMethodAndRaises*(typ; exceptions; prc) =
  clinicGenStaticMethodOfKindImpl(typ, Common, exceptions, prc, includeOriginal=true)

macro clinicGenMethodOfKind*(typ; kind: static[NPyMethodKind] = NPyMethodKind.Common, exceptions: untyped = []; prc) =
  clinicGenMethodOfKindImpl(typ, kind, exceptions, prc)

macro clinicGenMethod*(typ; prc) =
  clinicGenMethodOfKindImpl(typ, NPyMethodKind.Common, emptyB, prc)
macro clinicGenMethodRaises*(typ; exceptions; prc) =
  clinicGenMethodOfKindImpl(typ, NPyMethodKind.Common, exceptions, prc)


import std/macros
import ./fspathUtils/[decl, toval]
export decl, toval
import ./utils
imp Python, getargs/dispatch
imp Python, getargs/dispatch/sym2def

proc inplaceReplaceAt(params: NimNode, at: int, old: string, n: NimNode): bool =
  ## replace the first occurrence of `old` with `new` in `params`
  let typ = params[at]
  if typ.len == 0:
    if typ.eqIdent old:
      params[at] = n
      return true
  for i in 0..<typ.len:
    if typ.inplaceReplaceAt(i, old, n):
      result = true

proc normalizePathLikeParamForClinic(params, postdo: NimNode) =
  var retStrOrBytes = false
  for i in 1..<params.len:
    let p = params[i]
    if p.kind != nnkIdentDefs: continue
    for i in 0..<p.len - 2:
      p[i] = ident p[i].strVal
      # prevent `Error: cannot use symbol of kind 'param' as a 'var'`
    let p1 = p[^2]
    let PPStr = bindSym"PyPathStr"
    if p1.eqIdent"PathLike":
      p[^2] = PPStr
    elif (p1.kind == nnkBracketExpr and
          p1[0].eqIdent"PathLike"):
      p[^2] = PPStr
      let T = p1[1].strVal
      if params.inplaceReplaceAt(0, T, PPStr):
        # str or bytes based on arg type
        retStrOrBytes = true
  if retStrOrBytes:
    postdo.add newCall(bindSym"restorePathLikeParseState")

proc pathLikeProcDefForClinic(prc: NimNode, postdo: NimNode): NimNode =
  let emptyn = newEmptyNode()
  let params = prc.params.copyNimTree
  params.normalizePathLikeParamForClinic postdo
  result = nnkProcDef.newTree(
    prc.name,
    emptyn,
    emptyn,
    params,
    emptyn,
    emptyn,
    emptyn,
  )

template genClinicGen*(os; DefExceptions: untyped = []) {.dirty.} =
  bind clinicGenStaticMethodOfKindImpl, getProcDefFromSpec
  bind pathLikeProcDefForClinic
  bind ccconf
  const osS = astToStr(os)
  proc auditEventForPrc(prc: NimNode): string =
    var name = prc.name
    if name.kind == nnkPostfix:
      name = name[1]
    osS & '.' & name.strVal

  const osModuleS = osS & "Module"
  macro `clinicGen os`*(spec: typed, exceptions: untyped = [OSError],
      auditArgs: untyped = nil): untyped =
    var postdo = newStmtList()
    let prc = pathLikeProcDefForClinic(spec.getImpl, postdo)
    var conf = ccconf(prc.auditEventForPrc, auditArgs, postdo)
    clinicGenStaticMethodOfKindImpl(ident(osModuleS), NPyMethodKind.Common,
      exceptions, prc, conf=conf)

  macro `clinicGen os Sig`*(spec: untyped, exceptions: untyped = DefExceptions,
      auditArgs: untyped = nil): untyped =
    var postdo = newStmtList()
    let prc = pathLikeProcDefForClinic(getProcDefFromSpec spec, postdo)
    var conf = ccconf(prc.auditEventForPrc, auditArgs, postdo)
    clinicGenStaticMethodOfKindImpl(ident(osModuleS), NPyMethodKind.Common,
      exceptions, prc, conf=conf)


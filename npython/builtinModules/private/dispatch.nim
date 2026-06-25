
import std/macros
import ./fspathUtils/[decl, toval]
export decl, toval
import ./utils
imp Python, getargs/dispatch
imp Python, getargs/dispatch/sym2def

proc normalizePathLikeParamForClinic(p: NimNode) =
  if p.kind == nnkIdentDefs:
    for i in 0..<p.len - 2:
      p[i] = ident p[i].strVal
      # prevent `Error: cannot use symbol of kind 'param' as a 'var'`
    let p1 = p[^2]
    if p1.eqIdent"PathLike" or (
        p1.kind == nnkBracketExpr and p1[0].eqIdent"PathLike"):
      p[^2] = bindSym"PyPathStr"

proc pathLikeProcDefForClinic(prc: NimNode): NimNode =
  let emptyn = newEmptyNode()
  let params = prc.params.copyNimTree
  for i in 1..<params.len:
    params[i].normalizePathLikeParamForClinic
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
  bind pathLikeProcDefForClinic, normalizePathLikeParamForClinic
  const osS = astToStr(os)
  proc auditEventForPrc(prc: NimNode): string =
    var name = prc.name
    if name.kind == nnkPostfix:
      name = name[1]
    osS & '.' & name.strVal

  const osModuleS = osS & "Module"
  macro `clinicGen os`*(spec: typed, exceptions: untyped = [OSError],
      auditArgs: untyped = nil): untyped =
    let prc = pathLikeProcDefForClinic spec.getImpl
    clinicGenStaticMethodOfKindImpl(ident(osModuleS), NPyMethodKind.Common,
      exceptions, prc, auditArgs=auditArgs, auditEvent=prc.auditEventForPrc)

  macro `clinicGen os Sig`*(spec: untyped, exceptions: untyped = DefExceptions,
      auditArgs: untyped = nil): untyped =
    let prc = pathLikeProcDefForClinic getProcDefFromSpec spec
    clinicGenStaticMethodOfKindImpl(ident(osModuleS), NPyMethodKind.Common,
      exceptions, prc, auditArgs=auditArgs, auditEvent=prc.auditEventForPrc)


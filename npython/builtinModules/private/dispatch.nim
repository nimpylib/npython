
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
    if p[1].eqIdent"PathLike":
      p[1] = bindSym"PyPathStr"

proc pathLikeProcDefForClinic(prc: NimNode): NimNode =
  let emptyn = newEmptyNode()
  result = nnkProcDef.newTree(
    prc.name,
    emptyn,
    emptyn,
    prc.params.copyNimTree,
    emptyn,
    emptyn,
    emptyn,
  )
  for i in 1..<result.params.len:
    result.params[i].normalizePathLikeParamForClinic

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


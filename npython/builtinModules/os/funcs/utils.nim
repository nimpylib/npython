
import std/macros
import ./trans_pyimp
imp Python, getargs/dispatch
imp Python, getargs/dispatch/sym2def
impObjects [
  pyobject,
]
from pkg/pyio_abc import PathLike
import ./fspathUtils/[decl]
export decl

proc normalizeOsParamForClinic(p: NimNode) =
  if p.kind == nnkIdentDefs:
    for i in 0..<p.len - 2:
      p[i] = ident p[i].strVal
      # prevent `Error: cannot use symbol of kind 'param' as a 'var'`
    if p[1].eqIdent"PathLike":
      p[1] = bindSym"PyPathStr"

proc osProcDefForClinic(prc: NimNode): NimNode =
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
    result.params[i].normalizeOsParamForClinic

proc auditEventForOs(prc: NimNode): string =
  var name = prc.name
  if name.kind == nnkPostfix:
    name = name[1]
  "os." & name.strVal

macro clinicGenOs*(spec: typed, exceptions: untyped = [OSError],
    auditArgs: untyped = nil): untyped =
  let prc = spec.getImpl.osProcDefForClinic
  clinicGenStaticMethodOfKindImpl(ident"osModule", NPyMethodKind.Common,
    exceptions, prc, auditArgs=auditArgs, auditEvent=prc.auditEventForOs)

macro clinicGenOsSig*(spec: untyped, exceptions: untyped = [OSError],
    auditArgs: untyped = nil): untyped =
  let prc = spec.getProcDefFromSpec.osProcDefForClinic
  clinicGenStaticMethodOfKindImpl(ident"osModule", NPyMethodKind.Common,
    exceptions, prc, auditArgs=auditArgs, auditEvent=prc.auditEventForOs)

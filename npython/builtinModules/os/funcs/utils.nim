
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

macro clinicGenOs*(spec: typed, exceptions: untyped = [OSError]): untyped =
  clinicGenStaticMethodOfKindImpl(ident"osModule", NPyMethodKind.Common,
    exceptions, spec.getImpl.osProcDefForClinic)

macro clinicGenOsSig*(spec: untyped, exceptions: untyped = [OSError]): untyped =
  clinicGenStaticMethodOfKindImpl(ident"osModule", NPyMethodKind.Common,
    exceptions, spec.getProcDefFromSpec.osProcDefForClinic)

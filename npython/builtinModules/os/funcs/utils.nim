
import std/macros
import ../../private/utils
imp Python, getargs/dispatch
imp Python, getargs/dispatch/sym2def
impObjects [
  pyobject,
]
template gen(exceptions, procImpl): untyped =
  clinicGenStaticMethodOfKindImpl(ident"osModule", NPyMethodKind.Common,
    exceptions, procImpl)

macro clinicGenOs*(spec: typed, exceptions: untyped = [OSError]): untyped =
  gen(exceptions, spec.getImpl)

macro clinicGenOsSig*(spec: untyped, exceptions: untyped = [OSError]): untyped =
  gen(exceptions, spec.getProcDefFromSpec)


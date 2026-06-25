
import ./private/utils
import ./private/gen

impObjects [
  exceptions,
  moduleobjectImpl,
  noneobject,
  pyobject,
]
imp Python, getargs/dispatch

import ./collections/namedtuple as namedtupleModule
export namedtupleModule
import pkg/handy_sugars/trans_imp
impExpCwd collections, [
  defdict,
]

genModuleWithTypes collections, [
  "defaultdict",
]

macro genFunc(name: typed, exceptions: untyped = []) =
  clinicGenStaticMethodOfKindImpl(ident"collectionsModule",
    NPyMethodKind.Common,
    exceptions,
    name.getImpl)

genFunc namedtuple

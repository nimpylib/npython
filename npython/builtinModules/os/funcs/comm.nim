
template impOs(x) {.dirty.} =
  import pkg/posixos/x except audit
import ./trans_pyimp
impObjects [
  pyobject,
  exceptions,
  bltcommon,
]
import ../decl
impObjects exceptions/oserr/convert
import ./utils
impfspathUtils [decl, toval]
export decl, toval

methodMacroTmpl(osModule)


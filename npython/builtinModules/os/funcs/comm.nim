
template impOs(x) {.dirty.} =
  import pkg/posixos/x except audit
import ../../private/utils
impObjects [
  pyobject,
  exceptions,
  bltcommon,
]
import ../decl
impObjects exceptions/oserr/convert
import ./utils

methodMacroTmpl(osModule)


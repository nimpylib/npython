
template impObj(ls) {.dirty.} =
  import ../../Objects/ls
impObj [
  pyobject,
  bltcommon,
  exceptions,
  numobjects,
]
import ./init
methodMacroTmpl(mathModule)


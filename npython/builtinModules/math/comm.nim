
template imp(sub, ls) {.dirty.} =
  import ../../sub/ls
template impObj(ls) {.dirty.} =
  imp Objects, ls
impObj [
  pyobject,
  bltcommon,
  exceptions,
  numobjects,
]
import ./init
methodMacroTmpl(mathModule)


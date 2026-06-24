
import ../private/utils

impObjects [
  pyobject,
  stringobject,
]
import ./funcs

template gen(iskeywords) {.dirty.} =
  proc iskeywords*(x: PyStrObject): bool =
    if not x.isAscii: return
    x.str.asciiStr.iskeyword

gen iskeyword
gen issoftkeyword



import ./stringobject
import ../Utils/trans_imp
export stringobject
impExpCwd stringobject, [
  utf8apis, internal, meth, unicodeapis, fstring,
# XXX: import codec causes rec-dep
]

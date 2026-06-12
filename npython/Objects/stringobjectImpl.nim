
import ./stringobject
import ../Utils/trans_imp
export stringobject
impExpCwd stringobject, [
  utf8apis, internal, meth, unicodeapis, fstring,
  utf8apis_bytes,
# XXX: import codec causes rec-dep
]

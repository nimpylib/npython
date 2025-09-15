
import ../stringobject
proc PyUnicode_DecodeFSDefault*(s: string): PyStrObject =
  #TODO:decode
  newPyStr s

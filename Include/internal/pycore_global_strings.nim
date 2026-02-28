
import ../../Objects/stringobject

#TODO:str-internal
template pyIdImpl(s: string): PyStrObject =
  bind newPyAscii
  newPyAscii s
template pyId*(id: untyped{nkStrLit|nkRStrLit}): PyStrObject =
  ## `_Py_ID` in CPython
  bind pyIdImpl
  pyIdImpl id

template pyId*(id: untyped{~(nkRStrLit|nkStrLit)}): PyStrObject =
  ## `_Py_ID` in CPython
  bind pyIdImpl
  pyIdImpl astToStr id

const DU = "__"
template pyDUId*(id: untyped{~nkRStrLit}): PyStrObject =
  ## dunder(double underline) Py_ID
  bind pyIdImpl, DU
  pyIdImpl(DU & astToStr(id) & DU)

template Py_DECLARE_STR*(name; str: static string) =
  bind newPyAscii
  when not declared(name):
    let name = newPyAscii str
template Py_STR*(name): PyStrObject = name


import std/strformat
import ../[
  stringobject, pyobjectBase, exceptions,
]
template asAttrNameOrSetExc*(name: PyObject, exc: PyObject): PyStrObject =
  bind ofPyStrObject, typeName, newTypeError, newPyStr, PyStrObject
  bind formatValue, fmt
  if not ofPyStrObject(name):
    let n{.inject.} = typeName(name)
    exc = newTypeError newPyStr(
      fmt"attribute name must be string, not '{n:.200s}'",)
    return
  PyStrObject name

template asAttrNameOrRetE*(name: PyObject): PyStrObject =
  bind ofPyStrObject, typeName, newTypeError, newPyStr, PyStrObject
  asAttrNameOrSetExc(name, result)

template nameAsStr*{.dirty.} =
  when name is_not PyStrObject:
    let name = name.asAttrNameOrRetE


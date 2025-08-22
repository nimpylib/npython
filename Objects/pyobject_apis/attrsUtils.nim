
import std/strformat
import ../[
  stringobject, pyobjectBase, exceptions,
]
template asAttrNameOrRetE*(name: PyObject): PyStrObject =
  bind ofPyStrObject, typeName, newTypeError, newPyStr, PyStrObject
  bind formatValue, fmt
  if not ofPyStrObject(name):
    let n{.inject.} = typeName(name)
    return newTypeError newPyStr(
      fmt"attribute name must be string, not '{n:.200s}'",)
  PyStrObject name

template nameAsStr*{.dirty.} =
  when name is_not PyStrObject:
    let name = name.asAttrNameOrRetE


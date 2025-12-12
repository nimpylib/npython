
import std/strformat
import ./[
  pyobject,
  exceptions,
  typeobject,
  dictobject,
  tupleobjectImpl,
  stringobject,
]
export typeobject

import ./classobject


methodMacroTmpl(Type)

# type_new_init:type_new_alloc

implTypeMagic New(metaType: PyTypeObject, name: PyStrObject, 
                  bases: PyTupleObject, dict: PyDictObject):
  assert metaType == pyTypeObjectType
  assert bases.len == 0
  type Cls = PyInstanceObject
  let tp = newPyType[Cls]($name.str)
  tp.pyType = metaType
  tp.kind = PyTypeToken.Type
  tp.tp_dealloc = subtype_dealloc[Cls]
  tp.magicMethods.New = tpMagic(Instance, new)
  updateSlots(tp, dict)
  tp.dict = PyDictObject(tpMethod(Dict, copy)(dict))
  tp.typeReady true
  # XXX: CPython's `object` doesn't contains `__del__`
  tp

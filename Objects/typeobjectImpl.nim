
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
  if bases.len > 1:
    #TODO:mro
    return newNotImplementedError newPyAscii"multiple inheritance not supported yet"
  type Cls = PyInstanceObject
  var base = pyObjectType
  if bases.len > 0:
    let baseObj = bases[0]
    if not baseObj.ofPyTypeObject:
      base = baseObj.pyType
    else:
      base = PyTypeObject(baseObj)
  let tp = newPyType[Cls]($name.str, base=base)
  tp.pyType = metaType
  tp.kind = PyTypeToken.Type
  tp.tp_dealloc = subtype_dealloc[Cls]
  tp.magicMethods.New = tpMagic(Instance, new)
  updateSlots(tp, dict)
  tp.dict = PyDictObject(tpMethod(Dict, copy)(dict))
  tp.typeReady true
  # XXX: CPython's `object` doesn't contains `__del__`
  tp

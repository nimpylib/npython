
import std/strformat
import ./[
  pyobject,
  exceptions,
  typeobject,
  dictobject,
  tupleobjectImpl,
  stringobject,
]
import ./typeobject/[properties,
  default_generics,  object_new_init,
  ]
export typeobject
export properties

import ./classobject

import ./pyobject_apis/[
  attrsGeneric, strings,
]
import ../Python/getargs/dispatch
template baseMagic(name, meth) =
  pyObjectType.magicMethods.name = meth


baseMagic New, object_new_wrap
baseMagic init, object_init_wrap

baseMagic str, strDefault
baseMagic repr, reprDefault

baseMagic hash, hashDefault

baseMagic eq, eqDefault
baseMagic ne, neDefault

baseMagic getattr, PyObject_GenericGetAttr
baseMagic setattr, PyObject_GenericSetAttr
baseMagic delattr, PyObject_GenericDelAttr

proc object_format(self: PyObject, format_spec_obj: PyObject): PyObject {.clinicGenMeth("blt_obj_fmt", false).} =
  checkTypeOrRetTE(format_spec_obj, PyStrObject, pyStrObjectType)
  let format_spec = PyStrObject(format_spec_obj)
  if format_spec.len > 0:
    let n = self.pyType.typeName
    return newTypeError newPyStr &"unsupported format string passed to {n:.200s}.__format__"
  return PyObject_Str self

pyObjectType.bltinMethods["__format__"] = (blt_obj_fmt, false)

methodMacroTmpl(Type)
# this must be after properties import
pyTypeObjectType.typeReadyImpl(true)

# type_new_init:type_new_alloc

prepareIntFlagOr
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
  tp.tp_flags = Py_TPFLAGS.DEFAULT | Py_TPFLAGS.HEAPTYPE | Py_TPFLAGS.BASETYPE
  updateSlots(tp, dict)
  tp.dict = PyDictObject(tpMethod(Dict, copy)(dict))
  tp.typeReady true
  # XXX: CPython's `object` doesn't contains `__del__`
  tp

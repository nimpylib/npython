
import ./common #[
  pyobject,
  tupleobjectImpl,
]
]#

proc type_is_subtype_base_chain(a, b: PyTypeObject): bool =
  var a = a
  while true:
    if isType(a, b):
      return true
    a = a.base
    if a.isNil: break
  return b == pyObjectType

const HasMro = compiles((var a: PyObject; a.mro))
when HasMro:
 proc is_subtype_with_mro(a_mro: PyTupleObject, a, b: PyTypeObject): bool =
  if not a_mro.isNil:
    # Deal with multiple inheritance without recursion by walking the MRO tuple
    for i in a_mro:
      if i == b:
        return true
  else:
    return type_is_subtype_base_chain(a, b)

proc PyType_IsSubtype*(a, b: PyTypeObject): bool =
  when HasMro:
    is_subtype_with_mro(a.mro, a, b)
  else:
    type_is_subtype_base_chain(a, b)

proc isSubtype*(a, b: PyTypeObject): bool{.inline.} = PyType_IsSubtype(a, b)

proc PyObject_TypeCheck*(obj: PyObject, tp: PyTypeObject): bool =
  let objtp = obj.pyType
  objtp.isType(tp) or isSubtype(objtp, tp)

proc typeCheck*(ob: PyObject, tp: PyTypeObject): bool{.inline.} = PyObject_TypeCheck ob, tp

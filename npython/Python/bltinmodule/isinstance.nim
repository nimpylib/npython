import ../getargs/dispatch
import ../../Objects/[
  pyobject,
  tupleobjectImpl,
  boolobjectImpl,
  exceptions,
  stringobject,
]
import ../../Objects/typeobject/apis/subtype
import ./utils


proc isInstance*(obj: PyObject; cls: PyTypeObject): bool =
  obj.pyType.isType(cls) or obj.pyType.isSubtype(cls)


proc isInstance*(obj: PyObject; classes: PyTupleObject): bool =
  for clsObj in classes:
    if clsObj.isNil or not clsObj.ofPyTypeObject:
      return false
    if obj.isInstance(PyTypeObject(clsObj)):
      return true
  false


proc isinstance*(obj: PyObject; cls: PyObject): PyObject{.bltin_clinicGen.} =
  if cls.ofPyTypeObject:
    return newPyBool obj.isInstance(PyTypeObject(cls))
  if cls.ofPyTupleObject:
    for clsObj in PyTupleObject(cls):
      if clsObj.isNil or not clsObj.ofPyTypeObject:
        return newTypeError(newPyAscii("isinstance() arg 2 must be a type or tuple of types"))
      if obj.isInstance(PyTypeObject(clsObj)):
        return pyTrueObj
    return pyFalseObj
  newTypeError(newPyAscii("isinstance() arg 2 must be a type or tuple of types"))


template register_isinstance* =
  bind regfunc
  regfunc isinstance

import std/hashes
import ./pyobject 
import ./baseBundle
import ../Utils/utils

proc unhashable*(obj: PyObject): PyObject = newTypeError newPyAscii(
  "unhashable type '" & obj.pyType.name & '\''
)

proc rawHash*(obj: PyObject): Hash =
  ## for type.__hash__
  hash(obj.id)

# hash functions for py objects
# raises an exception to indicate type error. Should fix this
# when implementing custom dict
proc hash*(obj: PyObject): Hash = 
  ## for builtins.hash
  let fun = obj.pyType.magicMethods.hash
  if fun.isNil:
    return rawHash(obj)
  else:
    let retObj = fun(obj)
    if not retObj.ofPyIntObject:
      raise newException(DictError, retObj.pyType.name)
    return hash(PyIntObject(retObj))

proc rawEq*(obj1, obj2: PyObject): bool =
  ## for type.__eq__
  obj1.id == obj2.id

proc `==`*(obj1, obj2: PyObject): bool {. inline, cdecl .} =
  let fun = obj1.pyType.magicMethods.eq
  if fun.isNil:
    return rawEq(obj1, obj2)
  else:
    let retObj = fun(obj1, obj2)
    if not retObj.ofPyBoolObject:
      raise newException(DictError, retObj.pyType.name)
    return PyBoolObject(retObj).b

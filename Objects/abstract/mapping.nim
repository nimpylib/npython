
import ../[
  pyobject,
  exceptionsImpl,
  dictobjectImpl,
]
import ./dunder

proc PyMapping_GetOptionalItem*(obj: PyObject, key: PyObject, res: var PyObject): PyBaseErrorObject =
    if obj.ofExactPyDictObject:
      discard PyDictObject(obj).getItemRef(key, res, result)

    let r = PyObject_GetItem(obj, key)
    if r.isNil:
      return
    if r.isThrownException:
      result = PyBaseErrorObject r
      if result.ofPyKeyErrorObject:
        return nil

proc ofPyMapping*(o: PyObject): bool =
  o.getMagic(getItem) != nil


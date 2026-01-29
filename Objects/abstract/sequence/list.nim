
##XXX: rec-dep: ../sequence shall not import this, otherwise rec-dep
import ../../[
  pyobjectBase,
  exceptions,
  listobject,
  tupleobject,
]
import ../../exceptions/setter
import ../iter

proc PySequence_List*(v: PyObject): PyObject =
  let res = newPyList()
  retIfExc res.extend v
  return res

proc PySequence_Fast*(v: PyObject, errMsg: string): PyObject =
  if v.ofPyListObject or v.ofPyTupleObject:
    return v
  let it = PyObject_GetIter v
  if it.isThrownException:
    if it.ofPyTypeErrorObject:
      PyTypeErrorObject(it).setString errMsg
    return it
  PySequence_List it

template getCommonPySequence_Fast(s: PyObject, attr): untyped =
  bind ofPyListObject, PyListObject, PyTupleObject
  if s.ofPyListObject: PyListObject(s).attr
  else: PyTupleObject(s).attr

template PySequence_FAST_ITEMS*(s: PyObject): openArray[PyObject] =
  bind getCommonPySequence_Fast
  getCommonPySequence_Fast s, items

template PySequence_Fast_GET_SIZE*(s: PyObject): int =
  bind getCommonPySequence_Fast
  getCommonPySequence_Fast s, len

proc PySequence_Fast_GET_ITEM*(s: PyListObject; i: int): PyObject = s[i]
proc PySequence_Fast_GET_ITEM*(s: PyObject; i: int): PyObject =
  if s.ofPyListObject: PyListObject(s)[i]
  else: PyTupleObject(s)[i]

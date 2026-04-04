
import ../../[
  pyobjectBase,
  exceptions,
  listobject,
  tupleobject,
]
import ../iter

import ../helpers
proc PySequence_Tuple*(v: PyObject): PyObject =
  if v.isNil:
    return null_error()
  if v.ofExactPyTupleObject:
    return v
  if v.ofPyListObject:
    return (PyListObject v).toPyTuple

  let it = PyObject_GetIter v
  retIfExc it
  let res = newPyList()
  while true:
    let item = PyIter_Next it
    if item.isStopIter:
      break
    res.add item
  return res

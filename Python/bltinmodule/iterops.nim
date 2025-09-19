

import ../getargs/[
  dispatch,
  kwargs,
]
import ../../Objects/[
  pyobject,
  tupleobjectImpl,
  exceptions,
  noneobject,
  stringobject,
]
import ../../Objects/listobject/sort
import ../../Objects/abstract/[
  sequence/list,
]
import ../getargs/[tovals,]


proc sorted*(sequ: PyObject, key: PyObject = pyNone, reversed = false): PyObject{.bltin_clinicGen.} =
  result = PySequence_List(sequ)
  retIfExc result
  let newlist = PyListObject result
  retIfExc newlist.sort(key, reversed)
  return newlist

template register_iterops* =
  registerBltinFunction "sorted", builtin_sorted

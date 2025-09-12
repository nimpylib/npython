

import ../../Objects/[
  pyobject,
  exceptions,
]
template toval*(a: PyObject, val: var PyObject): PyBaseErrorObject =
  val = a
  PyBaseErrorObject nil

template genToVal*(T; fun){.dirty.} =
  template toval*(obj; val: var T): PyBaseErrorObject =
    bind fun
    fun(obj, val)

template genToValGeneric*(T; CT; GenericT){.dirty.} =
  genToVal T, `Py GenericT As CT`

template genToValGeneric*(T; GenericT){.dirty.} =
  genToValGeneric(T, T, GenericT)

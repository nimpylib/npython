
import ../[pyobject, exceptions]

template keyError*(other: PyObject): PyBaseErrorObject =
  let repr = other.pyType.magicMethods.repr(other)
  if repr.isThrownException:
    PyBaseErrorObject repr
  else:
    PyBaseErrorObject newKeyError PyStrObject(repr)

template handleBadHash*(res; body){.dirty.} =
  template setRes(e) = res = e
  handleHashExc setRes:
    body


import std/strformat
import ../[
  pyobject, exceptions,
  stringobject, iterobject,
]
import ./sequence
import ../../Utils/optres
export optres
proc PyIter_Check*(obj: PyObject): bool =
  let t = obj.getMagic(iternext)
  not t.isNil  # PY-DIFF: never be _PyObject_NextNotImplemented

template PyObject_GetIter*(o: PyObject): PyObject =
  bind newTypeError, newPyStr, getMagic, newPySeqIter
  bind fmt, formatValue
  bind ifPyNimSequence_Check, PySequence_Check
  let f = o.getMagic(iter)
  if f.isNil:
    ifPyNimSequence_Check(o):
      newPySeqIter(o.items)
    do:
      ifPyNimSequence_Check(o):
        newPySeqIter(o.items)
      do:
        if PySequence_Check(o):
          newPySeqIter(o)
        else:
          let n{.inject.} = o.pyType.name
          newTypeError newPyStr(
            fmt"'{n:.200s}' object is not iterable"
          )
  else: f(o)

proc iternext(iter: PyObject, item: var PyObject): GetItemRes =
    let tp_iternext = iter.getMagic iternext
    item = tp_iternext(iter)
    let isExc = item.isThrownException
    if not isExc:
      return Get

    #PyThreadState *tstate = _PyThreadState_GET();
    #[ When the iterator is exhausted it must return NULL;
     * a StopIteration exception may or may not be set. ]#
    if item.isStopIter:
      #_PyErr_Clear(tstate);
      item = nil
      return Missing
    # Error case: an exception (different than StopIteration) is set.
    return Error

proc PyIter_NextItem*(iter: PyObject, item: var PyObject): GetItemRes =
  let tp_iternext = iter.getMagic iternext
  if tp_iternext.isNil:
    let s = fmt"expected an iterator, got '{iter.typeName}'"
    item = newTypeError newPyStr s
    return Error
  iternext(iter, item)


proc PyIter_Next*(iter: PyObject): PyObject =
  discard iternext(iter, result)

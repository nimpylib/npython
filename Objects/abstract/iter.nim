
import std/strformat
import ../[
  pyobject, exceptions,
  stringobject, iterobject,
]
import ./sequence
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


import std/strformat
import ./pyobject
import ./numobjects
import ./[iterobject, exceptions, stringobject]
export PyNumber_Index, PyNumber_AsSsize_t, PyNumber_AsClampedSsize_t

    
template PySequence_Check*(o: PyObject): bool =
  ## PY-DIFF: we check whether o has items: seq[PyObject]
  when not compiles(o.items): false
  else: o.items is seq[PyObject]
template ifPySequence_Check*(o: PyObject, body) =
  when PySequence_Check(o): body
template ifPySequence_Check*(o: PyObject, body, elseDo): untyped =
  when PySequence_Check(o): body
  else: elseDo

proc PyIter_Check*(obj: PyObject): bool =
  let t = obj.getMagic(iternext)
  not t.isNil  # PY-DIFF: never be _PyObject_NextNotImplemented

template PyObject_GetIter*(o: PyObject): PyObject =
  bind newTypeError, newPyStr, getMagic, newPySeqIter
  bind fmt, formatValue
  bind ifPySequence_Check
  let f = o.getMagic(iter)
  if f.isNil:
    ifPySequence_Check(o):
      newPySeqIter(o.items)
    do:
      let n{.inject.} = o.pyType.name
      newTypeError newPyStr(
        fmt"'{n:.200s}' object is not iterable"
      )
  else: f(o)


import std/options
import pkg/intobject/decl
from pkg/pystrbytes_decl/strimpl import PyStr
from pkg/pystrbytes_decl/bytesimpl import PyBytes
import ./tovalsBase
export tovalsBase
import ../../Objects/[
  pyobject,
  exceptions,
  noneobject,
  boolobject,
  stringobject,
  byteobjects,
  listobject,
  tupleobject,
]
import ../../Objects/numobjects/intobject/ops_imp_warn
import ../../Objects/numobjects/floatobject


# == val to PyObject ==

template genToPyWithTBody(TT; body) {.dirty.} =
  proc toPy*[T](x: TT[T], res: var PyObject): PyBaseErrorObject = body
template genToPyWithBody(T; body) {.dirty.} =
  proc toPy*(x: T, res: var PyObject): PyBaseErrorObject = body
template via(f) {.dirty.} = res = f x
template genToPy(T; f) {.dirty.} = genToPyWithBody T, via f
template genToPyStrTyp(T) {.dirty.} =
  genToPyWithBody T:
    res = `new T` string(x)

genToPyWithBody PyObject:
  res = x

genToPyStrTyp PyStr
genToPyStrTyp PyBytes

genToPy bool, newPyBool
genToPy SomeInteger|IntObject, newPyInt
genToPy SomeFloat, newPyFloat
genToPy string|cstring|char, newPyStr
genToPyWithTBody openArray:
  var items = newSeq[PyObject](x.len)
  for i, item in x:
    retIfExc toPy(item, items[i])
  res = newPyList items

genToPyWithTBody Option:
  if x.isNone:
    res = pyNone
    return
  toPy(x.unsafeGet(), res)

type Tuple2[T] = (T, T)
genToPyWithTBody Tuple2:
  var e0, e1: PyObject
  retIfExc toPy(x[0], e0)
  retIfExc toPy(x[1], e1)
  res = newPyTuple([e0, e1])


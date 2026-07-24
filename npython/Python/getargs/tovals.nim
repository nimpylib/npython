
import std/options
import std/strformat
import pkg/intobject/decl
import ./tovalsBase
export tovalsBase
import ../../Objects/[
  pyobject,
  exceptions,
  stringobject,
  boolobjectImpl,
  noneobject,
]
import ../../Objects/numobjects/intobject/ops_imp_warn
import ../../Objects/numobjects/floatobject
import ../../Objects/abstract/sequence/list

genToValGeneric(float, double, Float)
genToValGeneric(float32, float, Float)
genToVal SomeInteger, PyNumber_AsSomeInteger

proc converterr(expected: string, arg: PyObject): string {.raises: [].} =
  fmt"must be {expected:.50s}, not {arg.typeName:.50s}"

proc handlestr(obj: PyObject, res: var PyStrObject): PyBaseErrorObject {.raises: [].} =
  if obj.ofPyStrObject:
    res = PyStrObject obj
    return
  newTypeError newPyAscii converterr("str", obj)
genToVal PyStrObject, handlestr

proc `handle %s`(x: PyObject, res: var string): PyBaseErrorObject {.raises: [].} =
  if x.ofPyStrObject:
    res = PyStrObject(x).asUTF8
    return
  newTypeError newPyAscii converterr("str", x)
genToVal string, `handle %s`
proc handleiobj(x: PyObject, res: var IntObject): PyBaseErrorObject {.raises: [].} =
  if x.ofPyIntObject:
    res = PyIntObject(x).v
    return
  newTypeError newPyAscii converterr("int", x)
genToVal IntObject, handleiobj

genToVal bool, PyObject_IsTrue

proc handleOption[T](x: PyObject, res: var Option[T]): PyBaseErrorObject =
  if x.isNil or x.isPyNone:
    res = none(T)
    return
  var val: T
  retIfExc toval(x, val)
  res = some(val)

genToVal1T Option, handleOption
type Tuple2[T] = (T, T)
proc handleTuple2[T](x: PyObject, res: var Tuple2[T]): PyBaseErrorObject =
  let items = PySequence_Fast(x, "argument must be an iterable")
  retIfExc items
  if PySequence_Fast_GET_SIZE(items) != 2:
    return newValueError newPyAscii(
      "argument must contain exactly two items")
  var e0, e1: T
  retIfExc toval(PySequence_Fast_GET_ITEM(items, 0), e0)
  retIfExc toval(PySequence_Fast_GET_ITEM(items, 1), e1)

  res = (e0, e1)

genToVal1T Tuple2, handleTuple2

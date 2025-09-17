
import std/strformat
import ./tovalsBase
export tovalsBase
import ../../Objects/[
  pyobject,
  exceptions,
  numobjects,
  stringobject,
  boolobjectImpl,
]

genToValGeneric(int, Ssize_t, Number)
genToValGeneric(float, double, Float)

proc converterr(expected: string, arg: PyObject): string =
  fmt"must be {expected:.50s}, not {arg.typeName:.50s}"

proc `handle %s`(x: PyObject, res: var string): PyBaseErrorObject =
  if x.ofPyStrObject:
    res = PyStrObject(x).asUTF8
    return
  newTypeError newPyAscii converterr("str", x)
genToVal string, `handle %s`

genToVal bool, PyObject_IsTrue


import pkg/pymath
include ./comm
impObj [
  iterobject,
  stringobject,
  tupleobject,
]
impObj abstract/sequence/tup

proc hypot*(args: varargs[PyObject]): PyObject =
  var res = 0.0
  var f: float
  for i in args:
    retIfExc PyFloat_AsDouble(i, f)
    res = hypot(res, f)
  newPyFloat res

implMathModuleMethod hypot(*coord): hypot(coord)

type Interrupt = object of CatchableError
  exc: PyBaseErrorObject
proc toFloat(x: PyObject): float =
  let exc = PyFloat_AsDouble(x, result)
  if exc.isNil.not:
    let e = new Interrupt
    e.exc = exc
    raise e
proc dist*(p, q: PyTupleObject): PyObject =
  newPyFloat try:
    pymath.dist(p.items, q.items)
  except Interrupt as e: return e.exc
  except ValueError as e: return newValueError newPyAscii e.msg

proc dist*(p, q: PyObject): PyObject =
  template tup(p): PyTupleObject =
    let t = PySequence_Tuple(p)
    retIfExc t
    PyTupleObject t
  dist(p.tup, q.tup)

implMathModuleMethod dist(p, q): dist(p, q)




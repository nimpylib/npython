
import pkg/pymath
import pkg/intobject
include ./comm
impObj [
  stringobject,
  tupleobject,
]
impObj abstract/sequence/tup

template reduce(hypot, T, newPyT, init, toV) {.dirty.} =
  proc hypot*(args: varargs[PyObject]): PyObject =
    var res = init
    var f: T
    for i in args:
      toV(i, f)
      res = hypot(res, f)
    `newPyT` res

  implMathModuleMethod hypot(*coord): hypot(coord)
template asgn(i, f) =
  retIfExc PyFloat_AsDouble(i, f)
reduce hypot, float, newPyFloat, 0.0, asgn
template toIntObj(o, i) =
  var pyi: PyIntObject
  retIfExc PyNumber_Index(o, pyi)
  i = pyi.v
template gcdlcm(gcd, init) {.dirty.} =
  reduce gcd, IntObject, newPyInt, init, toIntObj
template tryFirst: IntObject =
  var res: IntObject
  if args.len == 0: return pyIntZero
  args[0].toIntObj res
  res
gcdlcm gcd, tryFirst
gcdlcm lcm, intOne

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




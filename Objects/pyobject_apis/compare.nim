

import std/strformat
import ../[
  pyobject,
  stringobject,
  exceptions,
  notimplementedobject,
  boolobjectImpl,
]
import ../../Include/internal/pycore_ceval_rec
import ../../Include/cpython/pyerrors
import ../typeobject/apis/subtype

type PyCompareOp* = enum
  Py_LT
  Py_LE
  Py_EQ
  Py_NE
  Py_GT
  Py_GE

const
  Py_SwappedOp: array[PyCompareOp, PyCompareOp] =
    [Py_GT, Py_GE, Py_EQ, Py_NE, Py_LT, Py_LE]
  opstrings: array[PyCompareOp, string] = ["<", "<=", "==", "!=", ">", ">="]

using op: PyCompareOp
proc do_richcompare(v, w: PyObject, op; res: var PyObject): PyBaseErrorObject =
  ##[ Perform a rich comparison, raising TypeError when the requested comparison
   operator is not supported. ]##

  var checked_reverse_op = false

  template retIfImplOrExc(r) =
    if not r.isNotImplemented:
      if r.isThrownException:
        return PyBaseErrorObject r
      res = r
      return
  
  var f: BinaryMethod #richcmpfunc
  template doM(magic): bool =
    f = v.pyType.magicMethods.magic
    not f.isNil

  template hasOpAndFetchf(op): bool =
    case op
    of Py_LT: doM lt
    of Py_LE: doM le
    of Py_EQ: doM eq
    of Py_NE: doM ne
    of Py_GT: doM gt
    of Py_GE: doM ge

  let hasOp = hasOpAndFetchf(op)
  if (not Py_IS_TYPE(v, w.pyType) and
      PyType_IsSubtype(w.pyType, v.pyType) and
      hasOp):
      checked_reverse_op = true
      res = f(w, v) #, Py_SwappedOp[op])
      retIfImplOrExc res

  if hasOp:
      res = f(v, w)#, op)
      retIfImplOrExc res

  if not checked_reverse_op and hasOpAndFetchf(Py_SwappedOp[op]):
      res = f(w, v)
      retIfImplOrExc res
  #[ If neither object implements it, provide a sensible default
      for == and !=, but raise an exception for ordering. ]#
  case op
  of Py_EQ:
      res = newPyBool v == w
  of Py_NE:
      res = newPyBool v != w
  else:
      return newTypeError newPyStr(
        fmt"'{opstrings[op]}' not supported between instances of '{v.typeName:.100s}' and '{w.typeName:.100s}'"
      )

proc PyObject_RichCompare*(v, w: PyObject, op; res: var PyObject): PyBaseErrorObject =
  ##[ Perform a rich comparison with object result.  This wraps do_richcompare()
   with a check for NULL arguments and a recursion check. ]##
  #PyThreadState *tstate = _PyThreadState_GET();

  #assert(Py_LT <= op && op <= Py_GE);
  template chkE(x: PyObject): bool =
    if x.isNil:
      retIfExc PyErr_BadInternalCall()
    let isExc = x.isThrownException
    if isExc:
      return PyBaseErrorObject x
    isExc
  if chkE(v) or chkE(w):
    return

  withNoRecusiveCallOrRetE(" in comparison"):
    result = do_richcompare(v, w, op, res)


proc PyObject_RichCompareBool*(v, w: PyObject, op; resb: var bool): PyBaseErrorObject =
  ##[ Perform a rich comparison with integer result.  This wraps
   PyObject_RichCompare(), returning -1 for error, 0 for false, 1 for true. ]##

  #[ Quick result when objects are the same.
      Guarantees that identity implies equality. ]#
  template ret(i) =
    resb = i
    return
  if system.`==`(v, w):
    if op == Py_EQ:
      ret true
    elif op == Py_NE:
      ret false

  var res: PyObject
  let exc = PyObject_RichCompare(v, w, op, res)
  retIfExc exc

  if res.ofPyBoolObject:
    resb = PyBoolObject(res).isPyTrue
    #assert(_Py_IsImmortal(res));
  else:
    var b: bool
    retIfExc PyObject_IsTrue(res, b)
    resb = b


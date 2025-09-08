

import ../numobjects_comm
import ./[
  ops, fromx
]
include ./bytes_h


proc long_new_impl*(typ: PyTypeObject, x: PyObject, obase: PyObject): PyObject{.pyCFuncPragma.}
proc long_subtype_new(typ: PyTypeObject, x: PyObject, obase: PyObject): PyObject{.pyCFuncPragma.} =
  ##[ Wimpy, slow approach to tp_new calls for subtypes of int:
   first create a regular int from whatever arguments we got,
   then allocate a subtype instance and initialize it from
   the regular int.  The regular int is then thrown away.
  ]##

  when declared(PyType_IsSubtype):
    assert PyType_IsSubtype(typ, &PyLong_Type)
  let tmp = long_new_impl(pyIntObjectType, x, obase);
  retIfExc tmp
  let itmp = PyIntObject tmp
  var n = itmp.digitCount
  #[ Fast operations for single digit integers (including zero)
     assume that there is always at least one digit present. ]#
  if n == 0: n = 1

  result = typ.tp_alloc(typ, n)
  retIfExc result
  let newobj = PyIntObject result
  #newobj->long_value.lv_tag = tmp->long_value.lv_tag & ~IMMORTALITY_BIT_MASK;
  newobj.sign = itmp.sign
  newobj.digits = itmp.digits
  return newobj

proc long_new_impl*(typ: PyTypeObject, x: PyObject, obase: PyObject): PyObject{.pyCFuncPragma.} =
  if not typ.isType pyIntObjectType:
    return long_subtype_new(typ, x, obase)  # Wimp out
  if x.isNil:
    if not obase.isNil:
      return newTypeError newPyAscii"int() missing string argument"
    return pyIntZero
  # default base and limit, forward to standard implementation
  if obase.isNil:
    return PyNumber_Long(x)

  var exc: PyBaseErrorObject
  let base = PyNumber_AsSsize_t(obase, exc)
  retIfExc exc

  template retMayE(e: PyObject) =
    let res = e
    retIfExc e
    ret res
  template ret(obj) = return obj
  let o = x
  if o.ofPyStrObject:
    retMayE PyLong_FromUnicodeObject(PyStrObject o, base)
  if o.ofPyBytesObject:
    let b = PyBytesObject o
    retMayE PyLong_FromBytes(b.items, base)
  if o.ofPyByteArrayObject:
    let b = PyByteArrayObject o
    retMayE PyLong_FromBytes(b.items, base)

  return newTypeError newPyAscii"int() can't convert non-string with explicit base"

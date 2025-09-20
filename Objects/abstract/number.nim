

import ../[
  pyobject,
  exceptions,
  stringobject,
  numobjects,
]
import ../../Include/cpython/pyerrors
export PyNumber_Index, PyNumber_AsSsize_t, PyNumber_AsClampedSsize_t

proc PyLong_AsLongAndOverflow*(vv: PyObject, overflow: var IntSign, res: var int): PyBaseErrorObject =
  if vv.isNil: return PyErr_BadInternalCall()
  res = PyIntObject(
    if vv.ofPyIntObject: vv
    else:
      let ret = PyNumber_Index(vv)
      retIfExc ret
      ret
  ).toInt overflow

template genBOp(op){.dirty.} =
  proc `PyNumber op`*(v, w: PyObject): PyObject = v.callMagic(op, w)
template genUOp(op; pyopname){.dirty.} =
  proc `PyNumber pyopname`*(v: PyObject): PyObject = v.callMagic(op)

genBOp add
genBOp sub
genBOp mul
genBOp truediv

genUOp abs, Absolute
genUOp negative, Negative
genUOp positive, Positive
genUOp invert, Invert

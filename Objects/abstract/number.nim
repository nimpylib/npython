

import ../[
  pyobject,
  exceptions,
  stringobject,
  numobjects,
]
export PyNumber_Index, PyNumber_AsSsize_t, PyNumber_AsClampedSsize_t

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

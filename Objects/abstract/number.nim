

import ../[
  pyobject,
  exceptions,
  stringobject,
  numobjects,
]
import ../../Include/cpython/pyerrors
export PyNumber_Index, PyNumber_AsSsize_t, PyNumber_AsClampedSsize_t
import ./op_helpers

proc PyLong_AsLongAndOverflow*(vv: PyObject, overflow: var IntSign, res: var int): PyBaseErrorObject =
  if vv.isNil: return PyErr_BadInternalCall()
  res = PyIntObject(
    if vv.ofPyIntObject: vv
    else:
      let ret = PyNumber_Index(vv)
      retIfExc ret
      ret
  ).toInt overflow

template genBOp(op; opname){.dirty.} =
  binary_func(`PyNumber op`, op, opname)
template genUOp(op; pyopname){.dirty.} =
  proc `PyNumber pyopname`*(v: PyObject): PyObject = v.callMagic(op)

genBOp add, "+"
genBOp sub, "-"
genBOp mul, "*"
genBOp truediv, "/"  ## PyNumber_TrueDivide
genBOp floorDiv, "//"  ## PyNumber_FloorDivide
genBOp pow, "** or pow()"  ## PyNumber_PowerNoMod
genBOp Mod, "%"  ## PyNumber_Remainder


genBOp lshift, "<<"
genBOp rshift, ">>"
genBOp And, "&"
genBOp Or, "|"
genBOp Xor, "^"

genUOp abs, Absolute
genUOp negative, Negative
genUOp positive, Positive
genUOp invert, Invert

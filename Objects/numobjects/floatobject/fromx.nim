

from std/strutils import isSpaceAscii
from std/parseutils import parseFloat

import ./[decl, toval]
import ../[numobjects_comm, helpers]
import ../../../Python/[
  pystrtod,
]
import ../../stringobject/strformat
import ../../../Modules/unicodedata/decimalAndSpace
import ../../[
  byteobjects, 
]

proc float_from_string_inner(s: openArray[char], obj: PyObject): PyObject{.raises: [], cdecl.} =
  var
    i = 0
    last = s.high
  template retve =
    return newValueError PyStrFmt&"could not convert string to float: {obj:R}"
  # strip leading whitespace
  while s[i].isSpaceAscii:
    i.inc
    if i == s.len: retve
  # strip trailing whitespace
  while i < last and s[last].isSpaceAscii: last.dec

  #[We don't care about overflow or underflow.  If the platform
    supports them, infinities and signed zeros (on underflow) are
    fine.]#
  var x: float
  let n = s.toOpenArray(i, s.high).parseFloat(x)
  if i+n-1 != last: retve
  newPyFloat x


proc s2float(s: openArray[char], v: PyObject): PyObject{.inline.} =
  Py_string_to_number_with_underscores(s, "float", v, v,
    float_from_string_inner)

proc s2float(s: openArray[char], v: PyObject; res: var PyFloatObject): PyBaseErrorObject =
  let ret = s2float(s, v)
  retIfExc ret
  res = PyFloatObject ret

proc PyFloat_FromString*(v: PyStrObject; res: var PyFloatObject): PyBaseErrorObject{.raises: [].} =
  ## PyFloat_FromString for str
  let obj_s_buffer = PyUnicode_TransformDecimalAndSpaceToASCII(v)
  retIfExc obj_s_buffer
  let s_buffer = PyStrObject obj_s_buffer
  assert s_buffer.isAscii

  let s = s_buffer.asUTF8()
  s2float(s, v, res)


proc PyFloat_FromString*(v: PyObject; res: var PyFloatObject): PyBaseErrorObject =
  if v.ofPyStrObject: return PyFloat_FromString(v.PyStrObject, res)
  elif v.ofPyBytesObject:
    let b = v.PyBytesObject
    return s2float(b.items, v, res)
  elif v.ofPyByteArrayObject:
    let b = v.PyByteArrayObject
    return s2float(b.items, v, res)
  #TODO:buffer
  else:
    return newTypeError newPyStr fmt"float() argument must be a string or a real number, not '{v.typeName:.200s}'"

proc PyFloat_FromString*(v: PyObject|PyStrObject): PyObject =
  var res: PyFloatObject
  result = PyFloat_FromString(v, res)
  if result.isNil: result = res


proc PyNumber_Float*(o: PyObject; resf: var PyFloatObject): PyBaseErrorObject{.pyCFuncPragma.} =
  PyNumber_FloatOrIntImpl(o, resf, float):
    var val: float
    retIfExc res.toFloat val
    ret newPyFloat val

  # A float subclass with nb_float == NULL
  if o.ofPyFloatObject:
    ret newPyFloat o.PyFloatObject.asDouble

  retIfExc PyFloat_FromString(o, resf)


genNumberVariant Float, float


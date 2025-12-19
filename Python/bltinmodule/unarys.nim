

import std/strformat
import ../../Objects/[
  pyobject,
  tupleobjectImpl,
  exceptions,
  stringobjectImpl,
  byteobjects,
  boolobject,
  numobjects/intobject,
  abstract/number,
  pyobject_apis/typeCheck,
  pyobject_apis/strings,
]
import ./utils

import ../getargs/[kwargs, tovals, dispatch]

proc abs*(c: PyObject): PyObject{.bltin_clinicGen.} = PyNumber_Absolute c
proc ord*(c: PyObject): PyObject{.bltin_clinicGen.} =
  var size: int
  var typeChecked = false
  template chk(T; I) =
    if not typeChecked and c.`ofPy T Object`:
      let obj = `Py T Object`(c)
      size = obj.len
      if size == 1:
        let o = obj[0]
        return newPyInt cast[I](o)
      typeChecked = true
  chk Bytes, int
  chk Str, int32
  chk ByteArray, int
  if not typeChecked:
    return newTypeError newPyStr fmt"ord() expected a string of length 1, but {c.typeName:.200s} found"
  return newTypeError newPyStr fmt"ord() expected a character, but string of length {size} found"

proc bin*(n: PyObject): PyObject{.bltin_clinicGen.} = PyNumber_ToBase n, 2
proc oct*(n: PyObject): PyObject{.bltin_clinicGen.} = PyNumber_ToBase n, 8
proc hex*(n: PyObject): PyObject{.bltin_clinicGen.} = PyNumber_ToBase n, 16

proc chr*(c: PyObject): PyObject{.bltin_clinicGen.} =
  var overflow: IntSign
  var v: int
  retIfExc PyLong_AsLongAndOverflow(c, overflow, v)
  case overflow
  of Negative: v = low int
  of Positive: v = high int
  # Allow PyUnicode_FromOrdinal() to raise an exception
  of Zero: discard
  PyUnicode_FromOrdinal v

proc callable*(obj: PyObject): PyObject{.bltin_clinicGen.} = newPyBool obj.ofPyCallable
proc ascii*(us: PyObject): PyObject{.bltin_clinicGen.} = PyObject_ASCII us

template register_unarys* =
  bind regfunc
  regfunc ascii
  regfunc abs
  regfunc ord
  regfunc bin
  regfunc oct
  regfunc hex
  regfunc chr
  regfunc callable


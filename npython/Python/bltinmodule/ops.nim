
import std/strformat

import ./utils

import ../getargs/[
  dispatch,
  kwargs,
]
import ../../Objects/[
  pyobject,
  tupleobjectImpl,
  exceptions,
  stringobject,
  numobjects,
  noneobject,
]

import ../../Include/internal/pycore_global_strings
import ../../Objects/abstract/[
  number,
]
import ../../Objects/typeobject/apis/attrs
import ../getargs/[tovals]

import ../call

proc pow*(base: PyObject, exp: PyObject, `mod` = PyObject pyNone): PyObject{.bltin_clinicGen.} =
  if `mod`.isPyNone:
    PyNumber_PowerNoMod(base, exp)
  else:
    PyNumber_Power(base, exp, `mod`)

proc divmod*(x: PyObject, y: PyObject): PyObject{.bltin_clinicGen.} =
  PyNumber_Divmod(x, y)

proc round*(number: PyObject, ndigits = PyObject pyNone): PyObject{.bltin_clinicGen.} =
  let cb = PyObject_LookupSpecial(number, pyDUId round)
  if cb.isNil:
    return newTypeError newPyStr &"type {number.typeName:.100s} doesn't define __round__ method"
  if ndigits.isPyNone:
    cb.call()
  else:
    cb.call(ndigits)

template register_ops* =
  bind regfunc
  regfunc pow
  regfunc divmod
  regfunc round



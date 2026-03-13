
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

import ../../Objects/abstract/[
  number,
]
import ../getargs/[tovals]

proc pow*(base: PyObject, exp: PyObject, `mod` = PyObject pyNone): PyObject{.bltin_clinicGen.} =
  if `mod`.isPyNone:
    PyNumber_PowerNoMod(base, exp)
  else:
    PyNumber_Power(base, exp, `mod`)

proc divmod*(x: PyObject, y: PyObject): PyObject{.bltin_clinicGen.} =
  PyNumber_Divmod(x, y)

template register_ops* =
  bind regfunc
  regfunc pow
  regfunc divmod



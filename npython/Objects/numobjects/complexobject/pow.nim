
import ../numobjects_comm
import ./[
  decl, utils
]
import pkg/pycomplex

from pkg/float_utils/aritherr import ZeroDivisionError, OverflowError

proc `**`*(self, other: PyComplexObject): PyComplexObject =
  newPyComplex pow(self.v, other.v)

proc complex_pow*(selfNoCast, other: PyObject): PyObject =
  try:
    COMPLEX_BINOPimpl "** or pow()", pow
  except aritherr.ZeroDivisionError as e:
    return newZeroDivisionError newPyAscii e.msg
  except aritherr.OverflowError as e:
    return newOverflowError newPyAscii e.msg


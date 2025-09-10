
import std/strutils
import ../[
  pyobjectBase,
  stringobject,
  exceptions,
]
import ../../Include/internal/pycore_object
export Py_CheckSlotResult

proc null_error*(): PyBaseErrorObject =
  newSystemError newPyAscii"null argument to internal routine"

proc type_error*(s: string): PyBaseErrorObject =
  return newTypeError newPyStr s

proc type_errorn*(nstyleS: string; o: PyObject): PyBaseErrorObject{.raises: [].} =
  ## nim-style type_error, using `$n` based format of std/strutils
  var s = o.typeName.substr(0, 199)  # %.200s
  try: s = nstyleS % s
  except ValueError:
    return newSystemError newPyStr("invalid format string:" & nstyleS)
    #doAssert false, "bad PyUnicode_FromFormat call. msg: " & e.msg
  type_error s

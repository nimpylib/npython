

import ../../Utils/nexportc
import ../../Include/internal/pycore_global_strings
import ../abstract/call
import ../[
  pyobject,
  exceptions,
  stringobject,
]
import ../pyobject_apis/[strings, io]


using f: PyObject
proc PyFile_Flush*(f): PyBaseErrorObject {.npyexportc.} =
  retIfExc f.callMethod pyId"flush"

proc PyFile_Write*(s: PyStrObject; f): PyBaseErrorObject =
  retIfExc f.callMethod(pyId"write", s)

proc PyFile_Write*(s: string; f): PyBaseErrorObject {.npyexportc: "PyFile_WriteString".} =
  if f.isNil:
    return newSystemError newPyAscii"null file for PyFile_WriteString"
  PyFile_Write newPyStr s, f


proc PyFile_Write*(o: PyObject; f; flags = Py_PRINT_REPR): PyBaseErrorObject {.npyexportc: "PyFile_WriteObject".} =
  if f.isNil:
    return newTypeError newPyAscii"writeobject with NULL file"
  let s = if flags & Py_PRINT_RAW:
    PyObject_StrNonNil(o)
  else:
    PyObject_ReprNonNil(o)
  retIfExc s
  PyFile_Write PyStrObject s, f





import ../../Utils/nexportc
import ../../Include/internal/pycore_global_strings
import ../abstract/call
import ../[
  pyobject,
  exceptions,
]


using f: PyObject
proc PyFile_Flush*(f): PyBaseErrorObject {.npyexportc.} =
  retIfExc f.callMethod pyId"flush"



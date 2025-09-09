
import ../../Objects/[pyobjectBase,
  listobject, stringobject,
]
when newPyStr("") is_not PyStrObject:
  import ../../Objects/exceptions
import ./str

type
  PyConfigInitEnum* = enum
    ## Py_Initialize() API: backward compatibility with Python 3.6 and 3.7
    PyConfig_INIT_COMPAT = 1.cint,
    PyConfig_INIT_PYTHON = 2,
    PyConfig_INIT_ISOLATED = 3

proc asList*(list: openArray[Str]): PyObject =
  ## `_PyWideStringList_AsList`
  var pylist = newPyList(list.len)
  for i, v in list:
    let item = newPyStr(v)
    when item is_not PyStrObject:
      retIfExc item
    pylist[i] = item
  pylist



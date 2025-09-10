
import ../[
  pyobjectBase,
  stringobject,
  noneobject,
]
import ../../Python/[
  errors,
]
proc handleDelRes*(call: PyObject){.cdecl, raises: [].} =
  ## inner
  ## logic in `slot_tp_finalize`
  let res = call
  if res.isPyNone: return
  PyErr_FormatUnraisable newPyAscii"Exception ignored while calling deallocator " #TODO:stack

var magicNameStrs*: seq[PyStrObject]  # inner
for name in magicNames:
  magicNameStrs.add newPyStr(name)

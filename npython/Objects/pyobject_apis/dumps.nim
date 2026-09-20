
import ./io
import ../../Include/pystate/gil
import ../../Utils/[compat, nexportc]
import ../[pyobject,
  stringobject, exceptions,
]

proc PyUnstable_Object_DumpImpl(op: PyObject) {.cdecl.} =
  ## For debugging convenience.  See Misc/gdbinit for some useful gdb hooks
  when false:
    # It seems like the object memory has been freed:
    # don't access it to prevent a segmentation fault.
    if PyObject_IsFreed(op):
      errEchoCompat("<object at " & op.idStr & " is freed>\n")
      return

  # first, write fields which are the least likely to crash
  errEchoCompat "object address  : " & op.idStr
  #errEchoCompat "object refcount : " & $Py_REFCNT(op)

  let typ = op.pyType
  errEchoCompat "object type     : " & $typ
  errEchoCompat "object type name: " & (if typ.isNil: "NULL" else: typ.name)

  # the most dangerous part
  stderr.write "object repr     : "

  #let gil = PyGILState_Ensure()
  withPyGIL:
    #let exc = PyErr_GetRaisedException()

    #PyObject_Print(op, stderr, 0)
    discard PyObject_Println(op, stderr)

    #PyErr_SetRaisedException(exc)
    #PyGILState_Release(gil)
  stderr.flushFile

proc PyUnstable_Object_Dump*(op: PyObject) {.pyCFuncPragma, npyexportc.} =
  try: PyUnstable_Object_DumpImpl(op)
  except IOError: discard

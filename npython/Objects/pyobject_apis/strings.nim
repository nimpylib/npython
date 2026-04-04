
import std/strformat
import pkg/pyrepr
import ../[pyobject,
  stringobject, exceptions,
]
import ../../Utils/compat

proc PyObject_Repr*(obj: PyObject): PyObject{.raises: [].}
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
  var s = ""
  s &= "object repr     : "
  # (perform repr printing under GIL, preserving any raised exception)
  #let gil = PyGILState_Ensure()
  #let exc = PyErr_GetRaisedException()
  let sObj = PyObject_Repr(op)
  if sObj.isThrownException:
    return
  s &= $PyStrObject(sObj).str

  errEchoCompat s
  #PyObject_Print(op, stderr, 0)

  #PyErr_SetRaisedException(exc)
  #PyGILState_Release(gil)

proc PyUnstable_Object_Dump*(op: PyObject) {.cdecl, raises: [].} =
  try: PyUnstable_Object_DumpImpl(op)
  except IOError: discard

proc strDefault*(self: PyObject): PyObject {. cdecl .} =
  self.getMagic(repr)(self)

proc reprDefault*(self: PyObject): PyObject {. cdecl .} = 
  newPyString(fmt"<{self.typeName} object at {self.idStr}>")
proc PyObject_ReprNonNil*(obj: PyObject): PyObject =
  let fun = obj.getMagic(repr)
  if fun.isNil:
    return reprDefault obj
  result = fun(obj)
  retIfExc result
  result.errorIfNotString "__repr__"

template nullOr(obj; elseCall): PyObject =
  if obj.isNil: newPyAscii"<NULL>"
  else: elseCall obj

proc PyObject_Repr*(obj: PyObject): PyObject = obj.nullOr PyObject_ReprNonNil

proc PyObject_StrNonNil*(obj: PyObject): PyObject =
  let fun = obj.getMagic(str)
  if fun.isNil: return PyObject_ReprNonNil(obj)
  result = fun(obj)
  retIfExc result
  result.errorIfNotString "__str__"

proc PyObject_Str*(obj: PyObject): PyObject = obj.nullOr PyObject_StrNonNil

proc PyObject_ASCIINonNil*(us: PyObject): PyObject =
  let repr = PyObject_ReprNonNil us
  retIfExc repr
  # repr is guaranteed to be a PyUnicode object by PyObject_Repr
  let str = PyStrObject repr
  if str.isAscii:
    return str
  let s = pyasciiImpl $str
  newPyAscii s

proc PyObject_ASCII*(obj: PyObject): PyObject = obj.nullOr PyObject_ASCIINonNil

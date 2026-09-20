
import std/strformat
import ./sequence/checks; export checks
import ../[
  pyobject, exceptions,
]
import ../numobjects/intobject/[decl, ]
import ../typeobject/wraps
import ./helpers


proc PySequence_GetItemNonNil*(s: PyObject, i: Natural): PyObject =
  let gitem = s.getMagic(getitem)
  if gitem.isNil:
    return type_error fmt"'{s.typeName:.200s}' object does not support indexing"

  result = gitem(s, newPyInt i)
  assert Py_CheckSlotResult(s, "__getitem__", result)

template lenImpl(s: PyObject, L: var int; succDo) =
  if s.has_sq_length:
    retIfExc s.sq_length(L)
    assert Py_CheckSlotResult(s, "__len__", L>=0, s)
    succDo

proc PySequence_GetItemNonNil*(s: PyObject, i: int): PyObject{.raises: [].} =
  var i = i
  if s.has_sq_item:
    if i < 0:
      var L: int
      s.lenImpl L:
        i += L
    result = s.sq_item(i)
    assert Py_CheckSlotResult(s, "__getitem__", result)
    return
  return type_errorn("'$#' object does not support indexing", s)

proc PySequence_GetItem*(s: PyObject, i: int): PyObject =
  if s.isNil: return null_error()
  PySequence_GetItemNonNil s, i

proc PySequence_Size*(s: PyObject, res: var int): PyBaseErrorObject =
  s.lenImpl res:
    return
  return type_errorn("object of type '$#' has no len()", s)

template PySequence_Length*(s: PyObject, res: var int): PyBaseErrorObject =
  bind PySequence_Size
  PySequence_Size(s, res)

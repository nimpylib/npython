
import std/strformat
import ../[
  pyobject,
  exceptions,
  stringobject,
  notimplementedobject,
]
import ../typeobject/apis/subtype
import ../../Include/internal/pycore_object

proc binop_type_error(v, w: PyObject, op_name: string): PyTypeErrorObject =
  newTypeError newPyStr fmt"unsupported operand type(s) for {op_name:.100s}: '{v.typeName:.100s}' and '{w.typeName:.100s}'"

template BINARY_OP(v, w; magicop; opname) =
  bind BinaryMethod, isNotImplemented, pyNotImplemented
  bind PyType_IsSubtype, Py_CheckSlotResult
  let slotv = v.getMagic(magicop)
  var slotw: BinaryMethod
  if not Py_IS_TYPE(w, v.pyType):
    slotw = w.getMagic(magicop)
    if slotw == slotv:
      slotw = nil
  if not slotv.isNil:
    if not slotw.isNil and
       PyType_IsSubtype(w.pyType, v.pyType):
      result = slotw(v, w)
      if not result.isNotImplemented:
        return
      slotw = nil
    result = slotv(v, w)
    assert Py_CheckSlotResult(v, opname, result)
    if not result.isNotImplemented:
      return
  if not slotw.isNil:
    result = slotw(v, w)
    assert Py_CheckSlotResult(v, opname, result)
    if not result.isNotImplemented:
      return
  
  return pyNotImplemented

template binary_func*(op; magicop; opname){.dirty.} =
  bind BINARY_OP, binop_type_error, isNotImplemented

  proc op*(v, w: PyObject): PyObject{.pyCFuncPragma.} =
    ##[  Calling scheme used for binary operations:

    Order operations are tried until either a valid result or error:
      w.op(v,w)[*], v.op(v,w), w.op(v,w)

    [*] only when Py_TYPE(v) != Py_TYPE(w) && Py_TYPE(w) is a subclass of
        Py_TYPE(v)]##
    proc binary_op1(v, w: PyObject): PyObject = BINARY_OP(v, w, magicop, opname)
    result = binary_op1(v, w)
    if isNotImplemented(result):
      return binop_type_error(v, w, opname)


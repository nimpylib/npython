
import std/strformat
import ../[
  pyobject,
  exceptions,
  noneobject,
  stringobject,
  notimplementedobject,
]
import ../typeobject/apis/subtype
#import ../../Include/internal/pycore_object

proc binop_type_error(v, w: PyObject, op_name: string): PyTypeErrorObject =
  newTypeError newPyStr fmt"unsupported operand type(s) for {op_name:.100s}: '{v.typeName:.100s}' and '{w.typeName:.100s}'"

proc ternop_type_error(v, w, z: PyObject, op_name: string): PyTypeErrorObject =
  if z.isPyNone:
    return newTypeError newPyStr fmt"unsupported operand type(s) for {op_name:.100s}: '{v.typeName:.100s}' and '{w.typeName:.100s}'"
  newTypeError newPyStr fmt"unsupported operand type(s) for {op_name:.100s}: '{v.typeName:.100s}', '{w.typeName:.100s}', '{z.typeName:.100s}'"

template BINARY_OP(v, w; magicop; opname) =
  bind BinaryMethod, isNotImplemented, pyNotImplemented
  bind PyType_IsSubtype
  # XXX: do not use ```
  # Py_CheckSlotResult(v, opname, result)```
  # which FatalError when raising exception

  let slotv = v.getMagic(magicop)
  var slotw: BinaryMethod
  if not Py_IS_TYPE(w, v.pyType):
    slotw = w.getMagic(magicop)
    if slotw == slotv:
      slotw = nil
  template check(a1, op, res) =
    retIfExc res

  if not slotv.isNil:
    if not slotw.isNil and
       PyType_IsSubtype(w.pyType, v.pyType):
      result = slotw(v, w)
      if not result.isNotImplemented:
        return
      slotw = nil
    result = slotv(v, w)
    check(v, opname, result)
    if not result.isNotImplemented:
      return
  if not slotw.isNil:
    result = slotw(v, w)
    check(v, opname, result)
    if not result.isNotImplemented:
      return
  
  return pyNotImplemented

template TERNARY_OP(v, w, z; op_slot; op_name) =
  bind TernaryMethod, isNotImplemented, pyNotImplemented
  bind PyType_IsSubtype
  # XXX: do not use ```
  # Py_CheckSlotResult(v, opname, result)```
  # which FatalError when raising exception

  let slotv = v.getMagic(op_slot)
  var slotw: TernaryMethod
  if not Py_IS_TYPE(w, v.pyType):
    slotw = w.getMagic(op_slot)
    if slotw == slotv:
      slotw = nil
  template check(a1, op, res) =
    retIfExc res

  if not slotv.isNil:
    if not slotw.isNil and
       PyType_IsSubtype(w.pyType, v.pyType):
      result = slotw(v, w, z)
      if not result.isNotImplemented:
        return
      #[ can't do it ]#
      slotw = nil
    result = slotv(v, w, z)
    check(v, op_name, result)
    if not result.isNotImplemented:
      return
    #[ can't do it ]#
  if not slotw.isNil:
    result = slotw(v, w, z)
    check(w, op_name, result)
    if not result.isNotImplemented:
      return
    #[ can't do it ]#

  let slotz = z.getMagic(op_slot)
  if not slotz.isNil and slotz != slotv and slotz != slotw:
    result = slotz(v, w, z)
    check(z, op_name, result)
    if not result.isNotImplemented:
      return
    #[ can't do it ]#

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

template ternary_func*(op; magicop; opname){.dirty.} =
  bind TERNARY_OP, ternop_type_error, isNotImplemented

  proc op*(v, w, z: PyObject): PyObject{.pyCFuncPragma.} =
    ##[   Calling scheme used for ternary operations:

    Order operations are tried until either a valid result or error:
      v.op(v,w,z), w.op(v,w,z), z.op(v,w,z)
    ]##
    proc ternary_op1(v, w, z: PyObject): PyObject = TERNARY_OP(v, w, z, magicop, opname)
    result = ternary_op1(v, w, z)
    if isNotImplemented(result):
      return ternop_type_error(v, w, z, opname)


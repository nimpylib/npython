

import std/strformat
import ./pyobject
import ./[iterobject, exceptions, stringobject]

from ./numobjects import PyIntObject, PyNumber_AsSsize_t, PyNumber_Index, getClampedIndex
template optionalTLikeArg[T](args; i: int, def: T; mapper): T =
  if args.len > i: mapper args[i]
  else: def

template numAsIntOrRetE*(x: PyObject): int =
  ## interpret int or int-able object `x` to `system.int`
  bind PyNumber_AsSsize_t
  var res: int
  let e = x.PyNumber_AsSsize_t res
  if not e.isNil:
    return e
  res

template numAsClampedIndexOrRetE*(x: PyObject; size: int): int =
  ## interpret int or int-able object `x` to `system.int`, clamping result in `0..<size`
  bind PyNumber_Index, PyIntObject
  bind getClampedIndex
  let intObj = x.PyNumber_Index
  if intObj.isThrownException:
    return intObj
  intObj.PyIntObject.getClampedIndex(size)

template intLikeOptArgAt*(args: seq[PyObject]; i: int, def: int): int =
  ## parse arg `x: Optional[<object has __index__>] = None`
  bind optionalTLikeArg, numAsIntOrRetE
  optionalTLikeArg(args, i, def, numAsIntOrRetE)

template clampedIndexOptArgAt*(args: seq[PyObject]; i: int, def: int, size: int): int =
  ## parse arg `x: Optional[<object has __index__>] = None`, clamped result in `0..<size`
  bind optionalTLikeArg, numAsIntOrRetE
  template t(x): int{.genSym.} =
    numAsClampedIndexOrRetE(x, size)
  optionalTLikeArg(args, i, def, t)

template PySequence_Check*(o: PyObject): bool =
  ## PY-DIFF: we check whether o has items: seq[PyObject]
  when not compiles(o.items): false
  else: o.items is seq[PyObject]
template ifPySequence_Check*(o: PyObject, body) =
  when PySequence_Check(o): body
template ifPySequence_Check*(o: PyObject, body, elseDo): untyped =
  when PySequence_Check(o): body
  else: elseDo

proc PyIter_Check*(obj: PyObject): bool =
  let t = obj.getMagic(iternext)
  not t.isNil  # PY-DIFF: never be _PyObject_NextNotImplemented

template PyObject_GetIter*(o: PyObject): PyObject =
  bind newTypeError, newPyStr, getMagic, newPySeqIter
  bind fmt, formatValue
  bind ifPySequence_Check
  let f = o.getMagic(iter)
  if f.isNil:
    ifPySequence_Check(o):
      newPySeqIter(o.items)
    do:
      let n{.inject.} = o.pyType.name
      newTypeError newPyStr(
        fmt"'{n:.200s}' object is not iterable"
      )
  else: f(o)
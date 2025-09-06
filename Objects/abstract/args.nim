
import ../pyobject
from ../numobjects/intobject/decl import PyIntObject
from ../numobjects/intobject/ops import PyNumber_AsSsize_t, PyNumber_Index
from ../numobjects/intobject/idxHelpers import getClampedIndex
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


import std/strformat
import ./pyobject
import ./tupleobject
import ./[numobjects, noneobject]
import ./[exceptions, stringobject]
import ./sliceobject
export sliceobject

template longOr[T](a, b): T =
  when T is PyIntObject: a
  else: b

template I[T](obj: PySliceObject; attr; defVal: T): T =
  if obj.attr == pyNone: defVal
  else:
    let res = obj.attr.PyIntObject
    longOr[T](res, res.toInt) #  TODO: overflow

template negative(i: int): bool = i < 0

template CI[T](obj: PySliceObject; attr; defVal, size: T): T =
  var res = obj.I(attr, defVal)
  if res.negative: res = res + size
  res

proc stepAsLong*(slice: PySliceObject): PyIntObject = slice.I(step, pyIntOne)
proc stepAsInt*(slice: PySliceObject): int = slice.I(step, 1)
proc stopAsInt*[I: PyIntObject|int](slice: PySliceObject, size: I): I = slice.CI(stop, size, size)
proc startAsInt*[I: PyIntObject|int](slice: PySliceObject, size: I): I =
  slice.CI(start, longOr[I](pyIntZero, 0), size)

proc indices*(slice: PySliceObject, size: int): tuple[start, stop, stride: int] =
  let
    step = slice.stepAsInt 
    stop = slice.stopAsInt size
    start = slice.startAsInt size
  (start, stop, step)

# redeclare this for these are "private" macros

methodMacroTmpl(Slice)

implSliceMethod indices(size: PyIntObject):
  let
    step = self.stepAsLong
    stop = self.stopAsInt size
    start = self.startAsInt size
  newPyTuple(@[start.PyObject, stop, step])

proc dollar(self: PySliceObject): string =
  &"slice({$self.start}, {$self.stop}, {$self.step})"

method `$`*(self: PySliceObject): string = self.dollar

implSliceMagic repr:
  newPyAscii self.dollar


proc toNimSlice*(sliceStep1: PySliceObject, size: int): Slice[int] =
  let (start, stop, step) = sliceStep1.indices size
  let n1 = step < 0
  assert step.abs == 1
  if n1: stop+1 .. start
  else: start .. stop-1

iterator iterInt*(slice: PySliceObject, size: int): int =
  let
    step = slice.stepAsInt
    start = slice.startAsInt size
    stop = slice.stopAsInt size
  let neg = step < 0
  if neg:
    for i in countdown(start, stop+1, step): yield i
  else:
    for i in   countup(start, stop-1, step): yield i

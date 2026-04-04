
import std/strformat
import ../Python/getargs
import ./pyobject
import ./tupleobject
import ./numobjects/intobject/[decl, ops_imp_warn]
import ./noneobject
import ./[exceptions, stringobject]
import ./sliceobject
export sliceobject

template longOr[T](a, b): T =
  when T is PyIntObject: a
  else: b

template asClampedInt(i: PyIntObject): int =
  ## `_PyEval_SliceIndex`
  var res: int
  let exc = PyNumber_AsClampedSsize_t(i, res)
  assert exc.isNil
  res

template I[T](obj: PySliceObject; attr; defVal: T): T =
  if obj.attr == pyNone: defVal
  else:
    let res = obj.attr.PyIntObject
    longOr[T](res, res.asClampedInt)

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

template cal3parts(slice; size){.dirty.} =
  #TODO:slice ref PySlice_AdjustIndices
  let
    step = slice.stepAsLong
    stop = slice.stopAsInt size
    start = slice.startAsInt size

type Indices*[T] = tuple[start, stop, stride: T]

template sizeAsObj{.dirty.} =
  when size is int:
    let size = newPyInt size

proc indices*(slice: PySliceObject, size: PyIntObject): Indices[PyIntObject] =
  sizeAsObj
  cal3parts slice, size
  (start, stop, step)


proc indices*(slice: PySliceObject, size: int): Indices[int] =
  ## `PySlice_Unpack` and `adjust_slice_indexes`
  ## 
  ## result is clamped, as CPython does.
  sizeAsObj
  cal3parts slice, size
  (start.asClampedInt, stop.asClampedInt, step.asClampedInt)

template asIntOr(i: PyIntObject; elseDo): int =
  var ovf: bool
  let res = i.asLongAndOverflow(ovf)
  if ovf: elseDo
  res

proc indices*(slice: PySliceObject, size: PyIntObject|int; res: var Indices[int]): bool =
  ## returns false on overflow
  template asInt(i): int =
    asIntOr(i):
      return
  sizeAsObj
  cal3parts slice, size
  let
    stepV = step.asInt
    startV = start.asInt
    stopV = stop.asInt

  res = (startV, stopV, stepV)
  true

# redeclare this for these are "private" macros

methodMacroTmpl(Slice)

implSliceMethod indices(size: PyIntObject):
  cal3parts self, size
  PyTuple_Pack(start, stop, step)

proc dollar(self: PySliceObject): string =
  &"slice({$self.start}, {$self.stop}, {$self.step})"

method `$`*(self: PySliceObject): string = self.dollar

implSliceMagic New(tp: PyObject, *args):
  var
    start, stop, step: PyObject
  #noKeywords"slice"
  unpackOptArgs("slice", 1, 3, start, stop, step)

  # This swapping of stop and start is to maintain similarity with range()
  if stop.isNil:
    stop = start
    start = nil
  newPySlice(start, stop, step)

implSliceMagic repr:
  newPyAscii self.dollar

type
  ToNimSliceState* = enum
    tnssInvalidStep = -1  ## step is not 1 or -1
    tnssOk
    tnssOverflow  ## overflow in start, stop or step

template toNimSliceImpl(start, stop: int, step): Slice[int] =
  if step.negative:
    stop + 1 .. start
  else:
    start .. stop - 1

proc toNimSlice*(tup: Indices[int], size: int, res: var Slice[int]): bool =
  let
    stepV = tup.stride
    startV = tup.start
    stopV = tup.stop
  if stepV != 1 and stepV != -1: return

  res = toNimSliceImpl(startV, stopV, stepV)
  true

proc toNimSlice*(tup: Indices[PyIntObject], size: PyIntObject|int, res: var Slice[int]): ToNimSliceState =
  sizeAsObj
  let
    step = tup.stride
    start = tup.start
    stop = tup.stop
  var u: uint
  if not step.absToUInt(u): return tnssOverflow
  if u != 1: return tnssInvalidStep

  template asInt(i): int =
    asIntOr(i): return tnssOverflow
  let
    startV = start.asInt
    stopV = stop.asInt
  res = toNimSliceImpl(startV, stopV, step)
  tnssOk

proc toNimSlice*(slice: PySliceObject, size: PyIntObject|int, res: var Slice[int]): ToNimSliceState =
  sizeAsObj
  slice.indices(size).toNimSlice(size, res)

iterator iterInt*(ind: Indices[int]): int =
  let
    step = ind.stride
    start = ind.start
    stop = ind.stop
  let neg = step < 0
  if neg:
    for i in countdown(start, stop+1, step): yield i
  else:
    for i in   countup(start, stop-1, step): yield i

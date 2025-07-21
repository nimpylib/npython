import pyobject
import baseBundle
import ../Utils/rangeLen

declarePyType Slice(tpToken):
  start: PyObject
  stop: PyObject
  step: PyObject

# typically a slice is created then destroyed, so use a slice cache is very
# effective. However, this makes creating slice object dynamically impossible, so
# not adopted in NPython

proc newPySlice*(start, stop, step: PyObject): PyObject =
  let slice = newPySliceSimple()

  template setAttrTmpl(attr) =
    if attr.ofPyIntObject or attr.ofPyNoneObject:
      slice.attr = attr
    else:
      let indexFun = attr.pyType.magicMethods.index
      if indexFun.isNil:
        let msg = "slice indices must be integers or None or have an __index__ method"
        return newTypeError newPyAscii(msg)
      else:
        slice.attr = indexFun(attr)

  setAttrTmpl(start)
  setAttrTmpl(stop)
  setAttrTmpl(step)
  
  if slice.step.ofPyIntObject and (PyIntObject(slice.step).toInt == 0):
    return newValueError newPyAscii("slice step cannot be zero")
  slice


template I(obj: PySliceObject; attr; defVal: int): int =
  if obj.attr == pyNone: defVal
  else:
    obj.attr.PyIntObject.toInt #  TODO: overflow
template CI(obj: PySliceObject; attr; defVal, size: int): int =
  var res = obj.I(attr, defVal)
  if res < 0: res.inc size
  res

proc stepAsInt*(slice: PySliceObject): int = slice.I(step, 1)
proc stopAsInt*(slice: PySliceObject, size: int): int = slice.CI(stop, size, size)
proc startAsInt*(slice: PySliceObject, size: int): int = slice.CI(start, 0, size)

proc toNimSlice*(sliceStep1: PySliceObject, size: int): Slice[int] =
  let step = sliceStep1.stepAsInt 
  let n1 = step < 0
  let
    stop = sliceStep1.stopAsInt size
    start = sliceStep1.startAsInt size
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


proc calLen*(self: PySliceObject): int =
  ## Get the length of the slice.
  ## .. note:: python's slice has no `__len__`.
  ##   this is just a convenience method for internal use.
  template intOrNone(obj: PyObject, defaultValue: int): int =
    if obj.ofPyIntObject:
      PyIntObject(obj).toInt
    else:
      defaultValue
  rangeLen[int](
    intOrNone(self.start, 0),
    intOrNone(self.stop, 0),
    intOrNone(self.step, 1)
  )

proc getSliceItems*[T](slice: PySliceObject, src: openArray[T], dest: var (seq[T]|string)): PyObject =
  var start, stop, step: int
  let stepObj = slice.step
  if stepObj.ofPyIntObject:
    # todo: overflow
    step = PyIntObject(stepObj).toInt
  else:
    assert stepObj.ofPyNoneObject
    step = 1
  template setIndex(name: untyped, defaultValue: int) = 
    let `name Obj` = slice.`name`
    if `name Obj`.ofPyIntObject:
      name = getIndex(PyIntObject(`name Obj`), src.len, `<`)
    else:
      assert `name Obj`.ofPyNoneObject
      name = defaultValue
  var startDefault, stopDefault: int
  if 0 < step:
    startDefault = 0
    stopDefault = src.len
  else:
    startDefault = src.len - 1
    stopDefault = -1
  setIndex(start, startDefault)
  setIndex(stop, stopDefault)

  if 0 < step:
    while start < stop:
      dest.add(src[start])
      start += step
  else:
    while stop < start:
      dest.add(src[start])
      start += step
  pyNone

declarePyType Ellipsis(tpToken):
  discard

let pyEllipsis* = newPyEllipsisSimple()

proc dollar(self: PyEllipsisObject): string = "Ellipsis"
method `$`*(self: PyEllipsisObject): string =
  self.dollar

implEllipsisMagic repr:
  newPyAscii self.dollar

implEllipsisMagic New(tp: PyObject):
  return pyEllipsis

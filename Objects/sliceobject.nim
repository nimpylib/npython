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


# slice.indices defined in ./sliceobjectImpl

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

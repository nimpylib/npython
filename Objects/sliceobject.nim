import pyobject
import ./[
  exceptions, stringobject, noneobject,
]
import ./numobjects/intobject/[decl, ops, idxHelpers]
import ../Utils/rangeLen

declarePyType Slice(tpToken):
  start{.member,readonly.}: PyObject
  stop{.member,readonly.}: PyObject
  step{.member,readonly.}: PyObject

# typically a slice is created then destroyed, so use a slice cache is very
# effective. However, this makes creating slice object dynamically impossible, so
# not adopted in NPython

proc newPySlice*(start, stop, step: PyObject): PyObject =
  ## start, stop, step can be nil or `pyNone`_
  let slice = newPySliceSimple()

  template setAttrTmpl(attr) =
    if attr.isNil:
      slice.attr = pyNone
    elif attr.ofPyIntObject or attr.ofPyNoneObject:
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
  
  if slice.step.ofPyIntObject and (PyIntObject(slice.step).toIntOrRetOF == 0):
    return newValueError newPyAscii("slice step cannot be zero")
  slice


# slice.indices defined in ./sliceobjectImpl

proc calLen*(self: PySliceObject, res: var int): PyOverflowErrorObject =
  ## Get the length of the slice.
  ## .. note:: python's slice has no `__len__`.
  ##   this is just a convenience method for internal use.
  template intOrNone(obj: PyObject, defaultValue: int): int =
    if obj.ofPyIntObject:
      PyIntObject(obj).toIntOrRetOF
    else:
      defaultValue
  res=rangeLen[int](
    intOrNone(self.start, 0),
    intOrNone(self.stop, 0),
    intOrNone(self.step, 1)
  )

template calLenOrRetOF*(self: PySliceObject): int =
  bind calLen
  var res: int
  let ret = self.calLen res
  if not ret.isNil:
    return ret
  res

proc getSliceItems*[T](slice: PySliceObject, src: openArray[T], dest: var (seq[T]|string)): PyObject =
  bind getIndex
  var start, stop, step: int
  let stepObj = slice.step
  if stepObj.ofPyIntObject:
    step = PyIntObject(stepObj).toIntOrRetOF
  else:
    assert stepObj.ofPyNoneObject
    step = 1
  template setIndex(name: untyped, defaultValue: int, includeLen) = 
    let `name Obj` = slice.`name`
    if `name Obj`.ofPyIntObject:
      name = getIndex(PyIntObject(`name Obj`), src.len, includeLen)
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
  setIndex(start, startDefault, false)
  setIndex(stop, stopDefault, true)

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

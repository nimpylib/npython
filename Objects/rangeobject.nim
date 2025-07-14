import strformat

# import bigints

import pyobject
import baseBundle


declarePyType Range():
  start: PyIntObject
  ending: PyIntObject
  step: PyIntObject
  length: PyIntObject


implRangeMagic len:
  self.length

implRangeMagic repr:
  # todo: make it the same as CPython
  newPyString(fmt"range({self.start}, {self.ending}, {self.step}, {self.length})")


implRangeMagic init:
  for arg in args:
    if not arg.ofPyIntObject:
      # CPython uses duck typing here, anything behaves like an int
      # can be passed as argument. Too early for NPython to consider this.
      let msg = "range() only support int arguments"
      return newTypeError(msg)
  var start, ending, step: PyIntObject
  case args.len
  of 1:
    start = newPyInt(0)
    ending = PyIntObject(args[0])
    step = newPyInt(1)
  of 2:
    start = PyIntObject(args[0])
    ending = PyIntObject(args[1])
    step = newPyInt(1)
  of 3:
    start = PyIntObject(args[0])
    ending = PyIntObject(args[1])
    step = PyIntObject(args[2])
    if step.zero:
      let msg = "range() step must not be 0"
      return newValueError(msg)
  else:
    let msg = "range() expected 1-3 arguments"
    return newTypeError(msg)
  var length: PyIntObject
  # might need to refine this if duck typing is used
  # range(0, 2, 3): l = 1
  # range(0, 3, 3): l = 1
  # range(0, 3, 4): l = 2
  if step.positive:
    length = (ending - start + step - pyIntOne).floorDivNonZero step
  # range(1, -1, -1): l = 2
  else:
    assert step.negative
    length = (-ending + start - step - pyIntOne).floorDivNonZero -step
  if length.negative:
    length = pyIntZero
  self.start = start
  self.ending = ending
  self.step = step
  self.length = length
  pyNone


declarePyType RangeIter():
  start: PyIntObject
  step: PyIntObject
  length: PyIntObject
  index: PyIntObject


implRangeMagic iter:
  let iter = newPyRangeIterSimple()
  iter.start = self.start
  iter.step = self.step
  iter.length = self.length
  iter.index = newPyInt(0)
  iter


implRangeIterMagic iter:
  self

implRangeIterMagic iternext:
  if self.index.callMagic(lt, self.length) == pyTrueObj:
    result = self.start + self.index * self.step
    let newIndex = self.index.callMagic(add, newPyInt(1))
    self.index = PyIntObject(newIndex)
  else:
    return newStopIterError()


import std/sequtils
import strformat
import strutils

import pyobject
import baseBundle
import ./sliceobjectImpl
import iterobject
import ./tupleobject
import ../Utils/[utils, compat]

declarePyType List(reprLock, mutable, tpToken):
  items: seq[PyObject]


proc newPyList*: PyListObject = 
  newPyListSimple()

proc newPyList*(items: seq[PyObject]): PyListObject = 
  result = newPyList()
  result.items = items

template lsSeqToStr(ss): string = '[' & ss.join", " & ']'

genSequenceMagics "list",
  implListMagic, implListMethod,
  ofPyListObject, PyListObject,
  newPyListSimple, [mutable: read], [reprLockWithMsg"[...]", mutable: read],
  lsSeqToStr

proc len*(self: PyListObject): int{.inline.} = self.items.len

implListMagic setitem, [mutable: write]:
  if arg1.ofPyIntObject:
    let idx = getIndex(PyIntObject(arg1), self.len)
    self.items[idx] = arg2
    return pyNone
  if arg1.ofPySliceObject:
    let slice = arg1.PySliceObject
    let iterableToLoop = arg2
    case slice.stepAsInt
    of 1, -1:
      var ls: seq[PyObject]
      pyForIn it, iterableToLoop:
        ls.add it
      self.items[slice.toNimSlice(self.len)] = ls
    else:
      let (iterable, nextMethod) = getIterableWithCheck(iterableToLoop)
      if iterable.isThrownException:
        return iterable
      for i in iterInt(slice, self.len):
        let it = nextMethod(iterable)
        if it.isStopIter:
          break
        if it.isThrownException:
          return it
        self.items[i] = it
    return pyNone
  return newIndexTypeError(newPyAscii"list", arg1)

implListMagic delitem, [mutable: write]:
  if other.ofPyIntObject:
    let idx = getIndex(PyIntObject(other), self.len)
    self.items.delete idx
    return pyNone
  if other.ofPySliceObject:
    let slice = PySliceObject(other)
    case slice.stepAsInt:
    of 1, -1:
      self.items.delete slice.toNimSlice(self.len)
    else:
      for i in iterInt(slice, self.len):
        self.items.delete i
    return pyNone
  return newIndexTypeError(newPyAscii"list", other)


implListMethod append(item: PyObject), [mutable: write]:
  self.items.add(item)
  pyNone


implListMethod clear(), [mutable: write]:
  self.items.setLen 0
  pyNone


implListMethod copy(), [mutable: read]:
  let newL = newPyList()
  newL.items = self.items # shallow copy
  newL


# some test methods just for debugging
when not defined(release):
  # for lock testing
  implListMethod doClear(), [mutable: read]:
  # should fail because trying to write while reading
    self.clearPyListObjectMethod()

  implListMethod doRead(), [mutable: write]:
    # trying to read whiel writing
    return self.doClearPyListObjectMethod()


  # for checkArgTypes testing
  implListMethod aInt(i: PyIntObject), [mutable: read]:
    self.items.add(i)
    pyNone

  # for macro pragma testing
  macro hello(code: untyped): untyped = 
    code.body.insert(0, nnkCommand.newTree(ident("echoCompat"), newStrLitNode("hello")))
    code

  implListMethod hello(), [hello]:
    pyNone


implListMethod extend(other: PyObject), [mutable: write]:
  if other.ofPyListObject:
    self.items &= PyListObject(other).items
  else:
    pyForIn nextObj, other:
      self.items.add nextObj
  pyNone


implListMethod insert(idx: PyIntObject, item: PyObject), [mutable: write]:
  var intIdx: int
  if idx.negative:
    intIdx = 0
  elif self.items.len < idx:
    intIdx = self.items.len
  else:
    intIdx = idx.toInt
  self.items.insert(item, intIdx)
  pyNone


implListMethod pop(), [mutable: write]:
  if self.items.len == 0:
    let msg = "pop from empty list"
    return newIndexError newPyAscii(msg)
  self.items.pop

implListMethod remove(target: PyObject), [mutable: write]:
  var retObj: PyObject
  allowSelfReadWhenBeforeRealWrite:
    retObj = indexPyListObjectMethod(selfNoCast, @[target])
  if retObj.isThrownException:
    return retObj
  assert retObj.ofPyIntObject
  let idx = PyIntObject(retObj).toInt
  self.items.delete(idx)
  pyNone


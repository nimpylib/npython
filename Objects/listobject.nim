
import strformat
import strutils

import pyobject
import baseBundle
import sliceobject
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

implListMagic setitem, [mutable: write]:
  if arg1.ofPyIntObject:
    let idx = getIndex(PyIntObject(arg1), self.items.len)
    self.items[idx] = arg2
    return pyNone
  if arg1.ofPySliceObject:
    return newTypeError newPyAscii("store to slice not implemented")
  return newIndexTypeError(newPyAscii"list", arg1)

implListMagic delitem, [mutable: write]:
  if other.ofPyIntObject:
    let idx = getIndex(PyIntObject(other), self.items.len)
    self.items.delete idx
    return pyNone
  if other.ofPySliceObject:
    return newTypeError newPyAscii("delete slice not implemented")
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


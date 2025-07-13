
import strformat
import strutils

import pyobject
import baseBundle
import sliceobject
import iterobject
import ../Utils/[utils, compat]

declarePyType List(reprLock, mutable, tpToken):
  items: seq[PyObject]


proc newPyList*: PyListObject = 
  newPyListSimple()

proc newPyList*(items: seq[PyObject]): PyListObject = 
  result = newPyList()
  result.items = items


implListMagic contains, [mutable: read]:
  for idx, item in self.items:
    let retObj =  item.callMagic(eq, other)
    if retObj.isThrownException:
      return retObj
    if retObj == pyTrueObj:
      return pyTrueObj
  return pyFalseObj


implListMagic iter, [mutable: read]: 
  newPySeqIter(self.items)


implListMagic repr, [mutable: read, reprLock]:
  var ss: seq[string]
  for item in self.items:
    var itemRepr: PyStrObject
    let retObj = item.callMagic(repr)
    errorIfNotString(retObj, "__repr__")
    itemRepr = PyStrObject(retObj)
    ss.add(itemRepr.str)
  return newPyString("[" & ss.join(", ") & "]")


implListMagic len, [mutable: read]:
  newPyInt(self.items.len)

implListMagic getitem, [mutable: read]:
  if other.ofPyIntObject:
    let idx = getIndex(PyIntObject(other), self.items.len)
    return self.items[idx]
  if other.ofPySliceObject:
    let slice = PySliceObject(other)
    let newList = newPyList()
    let retObj = slice.getSliceItems(self.items.addr, newList.items.addr)
    if retObj.isThrownException:
      return retObj
    else:
      return newList
    
  return newIndexTypeError("list", other)


implListMagic setitem, [mutable: write]:
  if arg1.ofPyIntObject:
    let idx = getIndex(PyIntObject(arg1), self.items.len)
    self.items[idx] = arg2
    return pyNone
  if arg1.ofPySliceObject:
    return newTypeError("store to slice not implemented")
  return newIndexTypeError("list", arg1)


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


implListMethod count(target: PyObject), [mutable: read]:
  var count: int
  for item in self.items:
    let retObj = item.callMagic(eq, target)
    if retObj.isThrownException:
      return retObj
    if retObj == pyTrueObj:
      inc count
  newPyInt(count)

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

# implListMethod extend:
# todo
#

implListMethod index(target: PyObject), [mutable: read]:
  for idx, item in self.items:
    let retObj =  item.callMagic(eq, target)
    if retObj.isThrownException:
      return retObj
    if retObj == pyTrueObj:
      return newPyInt(idx)
  let msg = fmt"{target} is not in list"
  newValueError(msg)



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
    return newIndexError(msg)
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

implListMagic init:
  if 1 < args.len:
    let msg = fmt"list expected at most 1 args, got {args.len}"
    return newTypeError(msg)
  if self.items.len != 0:
    self.items.setLen(0)
  if args.len == 1:
    let (iterable, nextMethod) = getIterableWithCheck(args[0])
    if iterable.isThrownException:
      return iterable
    while true:
      let nextObj = nextMethod(iterable)
      if nextObj.isStopIter:
        break
      if nextObj.isThrownException:
        return nextObj
      self.items.add nextObj
  pyNone

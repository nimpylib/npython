import std/[sequtils, algorithm]
import strformat
import strutils

import pyobject
import baseBundle
import ./sliceobjectImpl
import ./hash
import iterobject
import ./tupleobjectImpl
import ./dictobject
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
  newPyList, [mutable: read], [reprLockWithMsg"[...]", mutable: read],
  lsSeqToStr, initWithDictUsingPairs=true


template genMutableSequenceMethods*(mapper, unmapper, S, Ele, beforeAppend){.dirty.} =
  ## `beforeAppend` body will be inserted before `append` method's implementation
  bind times, reverse
  bind ofPySliceObject, PySliceObject, getIterableWithCheck, stepAsInt, toNimSlice,
    iterInt, unhashable, delete
  bind echoCompat
  proc extend*(self: `Py S Object`, other: PyObject): PyObject =
    if other.`ofPy S Object`:
      self.items &= `Py S Object`(other).items
    else:
      pyForIn nextObj, other:
        self.items.add nextObj.mapper
    pyNone

  `impl S Magic` imul, [mutable: write]:
    var n: int
    let e = PyNumber_AsSsize_t(other, n)
    if not e.isNil:
      return e
    self.items = times(self.items, n)

  `impl S Magic` iadd, [mutable: write]: self.extend other

  `impl S Magic` setitem, [mutable: write]:
    if arg1.ofPyIntObject:
      let idx = getIndex(PyIntObject(arg1), self.len)
      self.items[idx] = arg2.mapper
      return pyNone
    if ofPySliceObject(arg1):
      let slice = PySliceObject(arg1)
      let iterableToLoop = arg2
      case stepAsInt(slice)
      of 1, -1:
        var ls: seq[Ele]
        pyForIn it, iterableToLoop:
          ls.add it.mapper
        self.items[toNimSlice(slice, self.len)] = ls
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
          self.items[i] = it.mapper
      return pyNone
    return newIndexTypeError(newPyAscii"list", arg1)

  `impl S Magic` delitem, [mutable: write]:
    if other.ofPyIntObject:
      let idx = getIndex(PyIntObject(other), self.len)
      self.items.delete idx
      return pyNone
    if ofPySliceObject(other):
      let slice = PySliceObject(other)
      case stepAsInt(slice):
      of 1, -1:
        delete(self.items, toNimSlice(slice, self.len))
      else:
        for i in iterInt(slice, self.len):
          self.items.delete i
      return pyNone
    return newIndexTypeError(newPyAscii"list", other)

  `impl S Magic` hash: unhashable self

  proc add*(self: `Py S Object`, item: PyObject): PyObject =
    beforeAppend
    self.items.add(item.mapper)
    pyNone

  `impl S Method` append(item: PyObject), [mutable: write]: self.add item

  `impl S Method` clear(), [mutable: write]:
    self.items.setLen 0
    pyNone

  `impl S Method` reverse(), [mutable: write]:
    reverse(self.items)
    pyNone

  `impl S Method` copy(), [mutable: read]:
    let newL = `newPy S`()
    newL.items = self.items # shallow copy
    newL


  # some test methods just for debugging
  when not defined(release):
    # for lock testing
    `impl S Method` doClear(), [mutable: read]:
    # should fail because trying to write while reading
      self.`clearPy S ObjectMethod`()

    `impl S Method` doRead(), [mutable: write]:
      # trying to read while writing
      return self.`doClearPy S ObjectMethod`()


    when Ele is PyObject:
      # for checkArgTypes testing
      `impl S Method` aInt(i: PyIntObject), [mutable: read]:
        self.items.add(i)
        pyNone

      # for macro pragma testing
      macro hello(code: untyped): untyped = 
        code.body.insert(0, nnkCommand.newTree(bindSym("echoCompat"), newStrLitNode("hello")))
        code

      `impl S Method` hello(), [hello]:
        pyNone


  `impl S Method` extend(other: PyObject), [mutable: write]: self.extend other


  `impl S Method` insert(idx: PyIntObject, item: PyObject), [mutable: write]:
    var intIdx: int
    if idx.negative:
      intIdx = 0
    elif self.items.len < idx:
      intIdx = self.items.len
    else:
      intIdx = idx.toIntOrRetOF
    self.items.insert(item.mapper, intIdx)
    pyNone


  `impl S Method` pop(), [mutable: write]:
    if self.items.len == 0:
      let msg = "pop from empty list"
      return newIndexError newPyAscii(msg)
    unmapper self.items.pop

  `impl S Method` remove(target: PyObject), [mutable: write]:
    var retObj: PyObject
    allowSelfReadWhenBeforeRealWrite:
      retObj = tpMethod(S, index)(selfNoCast, @[target])
    if retObj.isThrownException:
      return retObj
    assert retObj.ofPyIntObject
    let idx = PyIntObject(retObj).toIntOrRetOF
    self.items.delete(idx)
    pyNone


template asIs(x): untyped = x
genMutableSequenceMethods(asIs, asIs, List, PyObject): discard



import strformat
import strutils
import std/sets
import std/hashes

import pyobject
import baseBundle
import ./iterobject

import ./tupleobjectImpl
import ../Utils/[utils]
import ./hash

declarePyType Set(reprLock, mutable, tpToken):
  items: HashSet[PyObject]

declarePyType FrozenSet(reprLock, tpToken):
  items: HashSet[PyObject]
  setHash: bool
  privateHash: Hash

template setSeqToStr(ss): string =
  if ss.len == 0:
    self.pyType.name & "()"
  else:
    '{' & ss.join", " & '}'
template frozensetSeqToStr(ss): string =
  bind setSeqToStr
  "frozenset(" & setSeqToStr(ss) & ')'

template getItems(s: PyObject, elseDo): HashSet =
  if s.ofPySetObject: PySetObject(s).items
  elif s.ofPyFrozenSetObject: PyFrozenSetObject(s).items
  else: elseDo

template getItems(s: PyObject): HashSet =
  getItems s: return newNotImplementedError newPyAscii""   # TODO


template getItemsMayIter(s: PyObject): HashSet =
  getItems s:
    PyFrozenSetObject(
      pyFrozenSetObjectType.pyType.magicMethods.init(s, @[])
    ).items

template genOp(S, mutRead, pyOp, nop){.dirty.} =
  `impl S Magic` pyOp, mutRead:
    let res = `newPy S Simple`()
    res.items = nop(self.items, other.getItems)
    return res
template genMe(S, mutRead, pyMethod, nop){.dirty.} =
  `impl S Method` pyMethod(other: PyObject), mutRead:
    let res = `newPy S Simple`()
    res.items = nop(self.items, other.getItems)
    return res
template genBOp(S, mutRead, pyOp, nop){.dirty.} =
  `impl S Magic` pyOp, mutRead:
    if nop(self.items, other.getItems): pyTrueObj
    else: pyFalseObj
template genBMe(S, mutRead, pyMethod, nop){.dirty.} =
  `impl S Method` pyMethod(other: PyObject), mutRead:
    if nop(self.items, other.getItems): pyTrueObj
    else: pyFalseObj

template genSet(S, setSeqToStr, mutRead, mutReadRepr){.dirty.} =
  proc `newPy S`*: `Py S Object` =
    `newPy S Simple`()

  proc `newPy S`*(items: HashSet[PyObject]): `Py S Object` =
    result = `newPy S`()
    result.items = items

  proc `newPy S`*(items: openArray[PyObject]): `Py S Object` =
    `newPy S` items.toHashSet

  `impl S Method` copy(), mutRead:
    let newL = `newPy S`()
    newL.items = self.items # shallow copy
    newL
  
  genCollectMagics items,
    `impl S Magic`,
    `ofPy S Object`, `Py S Object`,
    mutRead, mutReadRepr,
    setSeqToStr


  `impl S Magic` init:
    if 1 < args.len:
      let msg = $S & fmt" expected at most 1 args, got {args.len}"
      return newTypeError newPyStr(msg)
    if self.items.len != 0:
      self.items.clear()
    if args.len == 1:
      pyForIn i, args[0]:
        self.items.incl i
    pyNone

  `impl S Magic` iter:
    genPyNimIteratorIter self.items

  
  genOp  S, mutRead, Or, `+`
  genMe  S, mutRead, union, `+`
  genOp  S, mutRead, And, `*`
  genMe  S, mutRead, interaction, `*`
  genOp  S, mutRead, Xor, `-+-`
  genMe  S, mutRead, symmetric_difference, `-+-`
  genOp  S, mutRead, sub, `-`
  genMe  S, mutRead, difference, `-`
  genBOp S, mutRead, le, `<`
  genBOp S, mutRead, eq, `==`
  genBMe S, mutRead, isdisjoint, disjoint
  genBMe S, mutRead, issubset, `<=`
  genBMe S, mutRead, issuperset, `>=`

genSet Set, setSeqToStr, [mutable: read], [mutable: read, reprLock]
genSet FrozenSet, frozensetSeqToStr, [], [reprLock]

proc hash*(self: PyFrozenSetObject): Hash = self.hashCollection
implFrozenSetMagic hash: newPyInt hash(self)
implSetMagic hash: unhashable self

implSetMethod update(args), [mutable: write]:
  for other in args:
    self.items.incl(other.getItemsMayIter)
  pyNone

implSetMethod intersection_update(args), [mutable: write]:
  for other in args:
    self.items = self.items * (other.getItemsMayIter)
  pyNone

implSetMethod difference_update(args), [mutable: write]:
  for other in args:
    self.items = self.items - (other.getItemsMayIter)
  pyNone

implSetMethod symmetric_difference_update(other: PyObject), [mutable: write]:
  self.items = self.items -+- (other.getItemsMayIter)


implSetMethod clear(), [mutable: write]:
  self.items.clear()
  pyNone

implSetMethod add(item: PyObject), [mutable: write]:
  self.items.incl(item)
  pyNone

implSetMethod `discard`(item: PyObject), [mutable: write]:
  if item.ofPyFrozenSetObject or item.ofPySetObject:
    self.items.excl item.getItems
  else:
    self.items.excl(item)
  pyNone

proc removeImpl(self: PySetObject, item: PyObject): PyObject =
  if self.items.missingOrExcl(item):
    newKeyError(PyStrObject(item.callMagic(repr)))
  else:
    pyNone

implSetMethod remove(item: PyObject), [mutable: write]:
  if item.ofPyFrozenSetObject or item.ofPySetObject:
    return self.removeImpl(item)
  else:
    pyForIn i, args[0]:
      result = self.removeImpl(i)
      if result.isThrownException:
        return

implSetMethod pop(), [mutable: write]:
  if self.items.len == 0:
    let msg = "pop from empty set"
    return newKeyError(newPyAscii msg)
  self.items.pop


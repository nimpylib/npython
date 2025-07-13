

import strformat
import strutils
import std/sets
import pyobject
import baseBundle


import ./tupleobject
import ../Utils/[utils]
import ./hash

declarePyType Set(reprLock, mutable, tpToken):
  items: HashSet[PyObject]

declarePyType FrozenSet(reprLock, tpToken):
  items: HashSet[PyObject]

template setSeqToStr(ss): string = '{' & ss.join", " & '}'

template getItems(s: PyObject): HashSet =
  if s.ofPySetObject: PySetObject(s).items
  elif s.ofPyFrozenSetObject: PyFrozenSetObject(s).items
  else: return newNotImplementedError""   # TODO

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

template genSet(S, mutRead, mutReadRepr){.dirty.} =
  proc `newPy S`*: `Py S Object` =
    `newPy S Simple`()

  proc `newPy S`*(items: HashSet[PyObject]): `Py S Object` =
    result = `newPy S`()
    result.items = items

  `impl S Method` copy(), mutRead:
    let newL = `newPy S`()
    newL.items = self.items # shallow copy
    newL
  
  genCollectMagics items,
    `impl S Magic`, `newPy S Simple`,
    `ofPy S Object`, `Py S Object`,
    mutRead, mutReadRepr,
    setSeqToStr


  `impl S Magic` hash:
    hashImpl items

  `impl S Magic` init:
    if 1 < args.len:
      let msg = $S & fmt" expected at most 1 args, got {args.len}"
      return newTypeError(msg)
    if self.items.len != 0:
      self.items.clear()
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
        self.items.incl nextObj
    pyNone

  
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

genSet Set, [mutable: read], [mutable: read, reprLock]
genSet FrozenSet, [], [reprLock]


implSetMethod clear(), [mutable: write]:
  self.items.clear()
  pyNone

implSetMethod add(item: PyObject), [mutable: write]:
  self.items.incl(item)
  pyNone

implSetMethod `discard`(item: PyObject), [mutable: write]:
  self.items.excl(item)
  pyNone

implSetMethod pop(), [mutable: write]:
  if self.items.len == 0:
    let msg = "pop from empty set"
    return newKeyError(msg)
  self.items.pop

# TODO: more ...

import strutils
import strformat

import pyobject
import baseBundle
import iterobject
import sliceobject


declarePyType Tuple(reprLock, tpToken):
  items: seq[PyObject]


proc newPyTuple*(items: seq[PyObject]): PyTupleObject = 
  result = newPyTupleSimple()
  # shallow copy
  result.items = items


template genCollectMagics*(items,
  implNameMagic, newPyNameSimple,
  ofPyNameObject, PyNameObject,
  mutRead, mutReadRepr, seqToStr){.dirty.} =


  implNameMagic contains, mutRead:
    for item in self.items:
      let retObj =  item.callMagic(eq, other)
      if retObj.isThrownException:
        return retObj
      if retObj == pyTrueObj:
        return pyTrueObj
    return pyFalseObj


  implNameMagic repr, mutReadRepr:
    var ss: seq[string]
    for item in self.items:
      var itemRepr: PyStrObject
      let retObj = item.callMagic(repr)
      errorIfNotString(retObj, "__repr__")
      itemRepr = PyStrObject(retObj)
      ss.add itemRepr.str
    return newPyString(seqToStr(ss))


  implNameMagic len, mutRead:
    newPyInt(self.items.len)


template genSequenceMagics*(nameStr,
    implNameMagic, implNameMethod;
    ofPyNameObject, PyNameObject,
    newPyNameSimple; mutRead, mutReadRepr;
    seqToStr): untyped{.dirty.} =

  bind genCollectMagics
  genCollectMagics items,
    implNameMagic, newPyNameSimple,
    ofPyNameObject, PyNameObject,
    mutRead, mutReadRepr, seqToStr

  implNameMagic add, mutRead:
    var res = newPyNameSimple()
    if other.ofPyNameObject:
      res.items = self.items & PyNameObject(other).items
      return res
    else:
      res.items = self.items
      let (iterable, nextMethod) = getIterableWithCheck(other)
      if iterable.isThrownException:
        return iterable
      while true:
        let nextObj = nextMethod(iterable)
        if nextObj.isStopIter:
          break
        if nextObj.isThrownException:
          return nextObj
        `&=` res.items, nextObj
      return res
  implNameMagic eq, mutRead:
    if not other.ofPyNameObject:
      return pyFalseObj
    let tOther = PyNameObject(other)
    if self.items.len != tOther.items.len:
      return pyFalseObj
    for i in 0..<self.items.len:
      let i1 = self.items[i]
      let i2 = tOther.items[i]
      let retObj = i1.callMagic(eq, i2)
      if retObj.isThrownException:
        return retObj
      assert retObj.ofPyBoolObject
      if not PyBoolObject(retObj).b:
        return pyFalseObj
    pyTrueObj


  implNameMagic init:
    if 1 < args.len:
      let msg = nameStr & fmt" expected at most 1 args, got {args.len}"
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


  implNameMagic iter, mutRead: 
    newPySeqIter(self.items)


  implNameMagic getitem:
    if other.ofPyIntObject:
      let idx = getIndex(PyIntObject(other), self.items.len)
      return self.items[idx]
    if other.ofPySliceObject:
      let slice = PySliceObject(other)
      let newObj = newPyNameSimple()
      let retObj = slice.getSliceItems(self.items.addr, newObj.items.addr)
      if retObj.isThrownException:
        return retObj
      else:
        return newObj
      
    return newIndexTypeError(nameStr, other)

  implNameMethod index(target: PyObject), mutRead:
    for idx, item in self.items:
      let retObj =  item.callMagic(eq, target)
      if retObj.isThrownException:
        return retObj
      if retObj == pyTrueObj:
        return newPyInt(idx)
    let msg = fmt"{target} is not in " & nameStr
    newValueError(msg)

  implNameMethod count(target: PyObject), mutRead:
    var count: int
    for item in self.items:
      let retObj = item.callMagic(eq, target)
      if retObj.isThrownException:
        return retObj
      if retObj == pyTrueObj:
        inc count
    newPyInt(count)

proc tupleSeqToString(ss: openArray[string]): string =
  ## one-element tuple must be out as "(1,)"
  result = "("
  case ss.len
  of 0: discard
  of 1:
    result.add ss[0]
    result.add ','
  else:
    result.add ss.join", "
  result.add ')'

genSequenceMagics "tuple",
  implTupleMagic, implTupleMethod,
  ofPyTupleObject, PyTupleObject,
  newPyTupleSimple, [], [reprLock],
  tupleSeqToString

template hashImpl*(items) =
  var h = self.id
  for item in self.items:
    h = h xor item.id
  return newPyInt(h)

implTupleMagic hash:
  hashImpl items

proc len*(t: PyTupleObject): int {. cdecl inline .} = 
  t.items.len

import std/hashes
import ./hash
import strformat

import pyobject
import baseBundle
import iterobject
import sliceobject


declarePyType Tuple(reprLock, tpToken):
  items: seq[PyObject]
  setHash: bool
  hash: Hash


proc newPyTuple*(items: seq[PyObject]): PyTupleObject = 
  result = newPyTupleSimple()
  # shallow copy
  result.items = items

proc newPyTuple*(items: openArray[PyObject]): PyTupleObject{.inline.} = 
  newPyTuple @items  

template genCollectMagics*(items,
  implNameMagic, newPyNameSimple,
  ofPyNameObject, PyNameObject,
  mutRead, mutReadRepr, seqToStr){.dirty.} =

  template len*(self: PyNameObject): int = self.items.len
  template `[]`*(self: PyNameObject, i: int): PyObject = self.items[i]
  iterator items*(self: PyNameObject): PyObject =
    for i in  self.items: yield i

  implNameMagic contains, mutRead:
    for item in self:
      let retObj =  item.callMagic(eq, other)
      if retObj.isThrownException:
        return retObj
      if retObj == pyTrueObj:
        return pyTrueObj
    return pyFalseObj


  implNameMagic repr, mutReadRepr:
    var ss: seq[UnicodeVariant]
    for item in self:
      var itemRepr: PyStrObject
      let retObj = item.callMagic(repr)
      errorIfNotString(retObj, "__repr__")
      itemRepr = PyStrObject(retObj)
      ss.add itemRepr.str
    return newPyString(seqToStr(ss))


  implNameMagic len, mutRead:
    newPyInt(self.len)


template genSequenceMagics*(nameStr,
    implNameMagic, implNameMethod;
    ofPyNameObject, PyNameObject,
    newPyNameSimple; mutRead, mutReadRepr;
    seqToStr; initWithDictUsingPairs=false): untyped{.dirty.} =

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
      pyForIn i, other:
        `&=` res.items, i
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
      return newTypeError newPyAscii(msg)
    if self.items.len != 0:
      self.items.setLen(0)
    if args.len == 1:
      let arg = args[0]
      template loop(a) =
        pyForIn i, a:
          self.items.add i
      when initWithDictUsingPairs:
        if arg.ofPyDictObject: loop tpMethod(Dict, items)(arg)
        else: loop arg
      else: loop arg
    pyNone


  implNameMagic iter, mutRead: 
    newPySeqIter(self.items)


  implNameMagic getitem:
    if other.ofPyIntObject:
      let idx = getIndex(PyIntObject(other), self.len)
      return self[idx]
    if other.ofPySliceObject:
      let slice = PySliceObject(other)
      let newObj = newPyNameSimple()
      let retObj = slice.getSliceItems(self.items, newObj.items)
      if retObj.isThrownException:
        return retObj
      else:
        return newObj
      
    return newIndexTypeError(newPyStr nameStr, other)

  implNameMethod index(target: PyObject), mutRead:
    for idx, item in self.items:
      let retObj =  item.callMagic(eq, target)
      if retObj.isThrownException:
        return retObj
      if retObj == pyTrueObj:
        return newPyInt(idx)
    let msg = fmt"{target} is not in " & nameStr
    newValueError(newPyStr msg)

  implNameMethod count(target: PyObject), mutRead:
    var count: int
    for item in self.items:
      let retObj = item.callMagic(eq, target)
      if retObj.isThrownException:
        return retObj
      if retObj == pyTrueObj:
        inc count
    newPyInt(count)

proc tupleSeqToString(ss: openArray[UnicodeVariant]): UnicodeVariant =
  ## one-element tuple must be out as "(1,)"
  result = newUnicodeUnicodeVariant "("
  case ss.len
  of 0: discard
  of 1:
    result.unicodeStr.add ss[0].toRunes
    result.unicodeStr.add ','
  else:
    result.unicodeStr.add ss.joinAsRunes", "
  result.unicodeStr.add ')'

genSequenceMagics "tuple",
  implTupleMagic, implTupleMethod,
  ofPyTupleObject, PyTupleObject,
  newPyTupleSimple, [], [reprLock],
  tupleSeqToString

template hashCollectionImpl*(items; hashForEmpty): Hash =
  var result: Hash
  if items.len == 0:
    result = hashForEmpty
  else:
    for item in items:
      result = result !& hash(item)
  !$result

proc hashCollection*[T: PyObject](self: T): Hash =
  if self.setHash: return self.hash
  result = self.items.hashCollectionImpl Hash self.pyType.id
  self.hash = result
  self.setHash = true

proc hash*(self: PyTupleObject): Hash = self.hashCollection 

implTupleMagic hash:
  newPyInt hash(self)

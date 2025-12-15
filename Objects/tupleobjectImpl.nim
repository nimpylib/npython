
import std/hashes
import ./hash
import strformat

import ./pyobject
import ./tupleobject
export tupleobject
import ./exceptions
import ./[iterobject, stringobject, sliceobject, noneobject, boolobject]
import ./numobjects/intobject/[decl, ops_imp_warn, idxHelpers]
import ./bltcommon; export bltcommon

methodMacroTmpl(Tuple)

template genGetitem*(nameStr, implNameMagic, newPyName, mutRead; getter: untyped = `[]`){.dirty.} =
  bind ofPySliceObject, getIndex, PySliceObject, getSliceItems
  bind ofPyIntObject, PyIntObject
  implNameMagic getitem, mutRead:
    if ofPyIntObject(other):
      let idx = getIndex(PyIntObject(other), self.len)
      return getter(self, idx)
    if ofPySliceObject(other):
      let slice = PySliceObject(other)
      let newObj = newPyName()
      let retObj = getSliceItems(slice, self.items, newObj.items)
      if retObj.isThrownException:
        return retObj
      else:
        return newObj
      
    return newIndexTypeError(newPyStr nameStr, other)

proc times*[T](s: openArray[T], n: int): seq[T] =
  result = newSeqOfCap[T](s.len * n)
  for _ in 1..n:
    result.add s

template genSequenceMagicsBesidesBaseCollect(nameStr,
    implNameMagic, implNameMethod;
    ofPyNameObject, PyNameObject,
    newPyName; mutRead;
    initWithDictUsingPairs=false): untyped{.dirty.} =
  bind PyNumber_AsSsize_t
  iterator pairs*(self: PyNameObject): (int, PyObject) =
    for i, v in  self.items.pairs: yield (i, v)
  implNameMagic mul, mutRead:
    var n: int
    let e = PyNumber_AsSsize_t(other, n)
    if not e.isNil:
      return e
    newPyName self.items.times n

  implNameMagic add, mutRead:
    var res = newPyName()
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

  genGetitem nameStr, implNameMagic, newPyName, mutRead

  implNameMethod index(target: PyObject), mutRead:
    for idx, item in self.items:
      let retObj =  item.callMagic(eq, target)
      if retObj.isThrownException:
        return retObj
      if isPyTrueObj(retObj):
        return newPyInt(idx)
    let msg = fmt"{target} is not in " & nameStr
    newValueError(newPyStr msg)

  implNameMethod count(target: PyObject), mutRead:
    var count: int
    for item in self.items:
      let retObj = item.callMagic(eq, target)
      if retObj.isThrownException:
        return retObj
      if isPyTrueObj(retObj):
        inc count
    return newPyInt(count)

template genSequenceMagics*(nameStr,
    implNameMagic, implNameMethod;
    ofPyNameObject, PyNameObject,
    newPyName; mutRead, mutReadRepr;
    seqToStr; initWithDictUsingPairs=false): untyped{.dirty.} =

  bind isPyTrueObj
  bind genCollectMagics, genSequenceMagicsBesidesBaseCollect, PyNumber_AsSsize_t, pyNone, newPyInt
  genCollectMagics items,
    implNameMagic,
    ofPyNameObject, PyNameObject,
    mutRead, mutReadRepr, seqToStr
  genSequenceMagicsBesidesBaseCollect nameStr,
    implNameMagic, implNameMethod,
    ofPyNameObject, PyNameObject,
    newPyName, mutRead,
    initWithDictUsingPairs


genSequenceMagicsBesidesBaseCollect "tuple",
  implTupleMagic, implTupleMethod,
  ofPyTupleObject, PyTupleObject,
  newPyTuple, [],
  false
#[
genSequenceMagics "tuple",
  implTupleMagic, implTupleMethod,
  ofPyTupleObject, PyTupleObject,
  newPyTuple, [], [reprLock],
  tupleSeqToString
]#

template hashCollectionImpl*(items; hashForEmpty): Hash =
  var result: Hash
  if items.len == 0:
    result = hashForEmpty
  else:
    for item in items:
      result = result !& hash(item)
  !$result

proc hashCollection*[T: PyObject](self: T): Hash =
  if self.setHash: return self.privateHash
  result = self.items.hashCollectionImpl Hash self.pyType.id
  self.privateHash = result
  self.setHash = true

proc hash*(self: PyTupleObject): Hash = self.hashCollection
proc clearhash(self: PyTupleObject){.inline.} =
  ## used after `[]=` to self.items
  self.setHash = false
template withSetitem*(self: PyTupleObject; acc; body) =
  ## unstable.
  ## take place of `PyTuple_SetItem`
  bind clearhash
  template acc: untyped = self.items
  body
  clearhash self

implTupleMagic hash:
  handleHashExc:
    result = newPyInt hash(self)

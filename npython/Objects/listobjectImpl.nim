
import std/sequtils
import ./[
  pyobject,
  exceptions,
  noneobject,
  boolobject,
  stringobject,
  listobject,
  dictobjectImpl,
]
export listobject
import ./[
  sliceobjectImpl,
  tupleobjectImpl,
]
import ./iterobject

import ./numobjects/intobject/[ops_imp_warn, idxHelpers]
import ../Utils/trans_imp
impExpCwd listobject, [
  bltin_sort, sort,
]

methodMacroTmpl(List)
registerBltinMethod pyListObjectType, "sort", builtin_sort

genSequenceMagicsBesidesBaseCollect "list",
  implListMagic, implListMethod,
  ofPyListObject, PyListObject,
  newPyList, [mutable: read],
  initWithDictUsingPairs=true

template genImpl(mapper, unmapper, S, Ele, beforeAppend){.dirty.} =
  bind delete
  bind times, getIndex, iterInt, indices
  bind pyNone
  bind ofPySliceObject, PySliceObject, getIterableWithCheck, toNimSlice
  `impl S Magic` imul, [mutable: write]:
    var n: int
    let e = PyNumber_AsSsize_t(other, n)
    if not e.isNil:
      return e
    self.items = times(self.items, n)

  `impl S Magic` setitem, [mutable: write]:
    if arg1.ofPyIntObject:
      let idx = getIndex(PyIntObject(arg1), self.len)
      self[idx] = arg2.mapper
      return pyNone
    if ofPySliceObject(arg1):
      let slice = PySliceObject(arg1)
      let iterableToLoop = arg2
      let L = self.len
      var nslice: Slice[int]
      let ind = slice.indices(L)

      if ind.toNimSlice(L, nslice):
        var ls: seq[Ele]
        pyForIn it, iterableToLoop:
          ls.add it.mapper
        self[nslice] = ls
      else:
        let (iterable, nextMethod) = getIterableWithCheck(iterableToLoop)
        retIfExc iterable
        for i in iterInt(ind):
          let it = nextMethod(iterable)
          if it.isStopIter:
            break
          retIfExc it
          self[i] = it.mapper
      return pyNone
    return newIndexTypeError(newPyAscii"list", arg1)

  `impl S Magic` delitem, [mutable: write]:
    if other.ofPyIntObject:
      let idx = getIndex(PyIntObject(other), self.len)
      self.items.delete idx
      return pyNone
    if ofPySliceObject(other):
      let slice = PySliceObject(other)
      let L = self.len
      var nslice: Slice[int]
      let ind = slice.indices(L)

      if ind.toNimSlice(L, nslice):
        delete(self.items, nslice)
      else:
        for i in iterInt(ind):
          self.items.delete i
      return pyNone
    return newIndexTypeError(newPyAscii"list", other)

  `impl S Method` remove(target: PyObject), [mutable: write]:
    var retObj: PyObject
    allowSelfReadWhenBeforeRealWrite:
      retObj = tpMethod(S, index)(selfNoCast, @[target])
    retIfExc retObj
    assert retObj.ofPyIntObject
    let idx = PyIntObject(retObj).toIntOrRetOF
    self.items.delete(idx)
    return pyNone

template asIs(x): untyped = x
genImpl(asIs, asIs, List, PyObject): discard

template genMutableSequenceMethods*(mapper, unmapper, S, Ele, beforeAppend){.dirty.} =
  ## `beforeAppend` body will be inserted before `append` method's implementation
  bind genMutableSequenceMethods_NotDepWarn, genImpl
  genMutableSequenceMethods_NotDepWarn mapper, unmapper, S, Ele, beforeAppend
  genImpl  mapper, unmapper, S, Ele, beforeAppend


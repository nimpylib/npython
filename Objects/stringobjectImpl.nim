
import std/strformat
import pyobject
import baseBundle
import stringobject
import ./sliceobject
import ../Utils/sequtils

export stringobject


# redeclare this for these are "private" macros

methodMacroTmpl(Str)


implStrMagic eq:
  if not other.ofPyStrObject:
    return pyFalseObj
  if self.str == PyStrObject(other).str:
    return pyTrueObj
  else:
    return pyFalseObj


implStrMagic str:
  self

implStrMagic len:
  newPyInt self.len

implStrMagic repr:
  newPyString(repr self)


implStrMagic hash:
  newPyInt(self.hash)

# TODO: encoding, errors params
implStrMagic New(tp: PyObject, obj: PyObject):
  # ref: unicode_new -> unicode_new_impl -> PyObject_Str
  let fun = obj.getMagic(str)
  if fun.isNil:
    return obj.callMagic(repr)
  result = fun(obj)
  if not result.ofPyStrObject:
    return newTypeError newPyStr(
      &"__str__ returned non-string (type {result.pyType.name:.200s})")


implStrMagic add(i: PyStrObject):
  self & i

template itemsAt(self: PyStrObject, i: int): PyStrObject =
  # this is used in `getitem` magic
  #{.push boundChecks: off.}
  if self.str.ascii:
    newPyString self.str.asciiStr[i]
  else:
    newPyString self.str.unicodeStr[i]
  #{.pop.}
type Getter = proc(i: int): PyStrObject
declarePyType StrIter():
    ascii: bool
    len: int
    items: UnicodeVariant
    idx: int
    getItem: Getter

implStrIterMagic iter:
  self

implStrIterMagic iternext:
  if self.idx == self.len:
    return newStopIterError()
  result = self.getItem self.idx
  inc self.idx


proc newPyStrIter*(s: PyStrObject): PyStrIterObject = 
  result = newPyStrIterSimple()
  result.items = s.str
  result.ascii = s.str.ascii
  result.len = s.len
  result.getItem = if result.ascii:
    proc(i: int): PyStrObject = newPyString s.str.asciiStr[i]
  else:
    proc(i: int): PyStrObject = newPyString s.str.unicodeStr[i]

template findExpanded(it1, it2): int = uint32.findWithoutMem(it1, it2)
iterator findAllExpanded[A, B](it1: A, it2: B): int =
  for i in uint32.findAllWithoutMem(it1, it2): yield i

when true:
  # copied and modified from ./tupleobject.nim
  implStrMagic iter: 
    newPyStrIter(self)

  implStrMagic contains(o: PyStrObject):
    let res = doKindsWith2It(self.str, o.str):
      it1.contains it2
      it1.findExpanded(it2) > 0
      it1.findExpanded(it2) > 0
      it1.contains it2
    if res: pyTrueObj
    else: pyFalseObj


  implStrMagic getitem:
    if other.ofPyIntObject:
      let idx = getIndex(PyIntObject(other), self.len)
      return self.itemsAt idx
    if other.ofPySliceObject:
      let slice = PySliceObject(other)
      template tgetSliceItems(attr): untyped =
        slice.getSliceItems(self.str.attr, newObj.str.attr)
      var
        newObj: PyStrObject
        retObj: PyObject
      if self.str.ascii:
        newObj = newPyString newAsciiUnicodeVariantOfCap slice.calLenOrRetOF
        retObj = tgetSliceItems(asciiStr)
      else:
        newObj = newPyString newUnicodeUnicodeVariantOfCap slice.calLenOrRetOF
        retObj = tgetSliceItems(unicodeStr)
      if retObj.isThrownException:
        return retObj
      else:
        return newObj


  implStrMethod index(target: PyStrObject):
    let res = doKindsWith2It(self.str, target.str):
      sequtils.find(it1, it2)
      it1.findExpanded(it2)
      it1.findExpanded(it2)
      sequtils.find(it1, it2)
    if res >= 0:
      return newPyInt(res)
    let msg = "substring not found"
    newValueError(newPyAscii msg)

  implStrMethod count(target: PyStrObject):
    var count: int
    template cntAll(it) =
      for _ in it: count.inc
    doKindsWith2It(self.str, target.str):
      cntAll it1.findAll(it2)
      cntAll it1.findAllExpanded(it2)
      cntAll it1.findAllExpanded(it2)
      cntAll it1.findAll(it2)
    newPyInt(count)

implStrMethod find(target: PyStrObject):
  let res = doKindsWith2It(self.str, target.str):
    sequtils.find(it1, it2)
    it1.findExpanded(it2)
    it1.findExpanded(it2)
    sequtils.find(it1, it2)
  newPyInt(res)

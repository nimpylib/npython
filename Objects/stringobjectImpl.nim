
import std/strformat
import pyobject
import baseBundle
import stringobject
import ./sliceobject
import ./pyobject_apis
import ../Utils/sequtils
from ../Python/errors import PyErr_BadArgument
from ./abstract_without_call import clampedIndexOptArgAt

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


proc PyUnicode_AsUTF8AndSize*(obj: PyObject, utf8: var string, size: var int): PyBaseErrorObject =
  if not obj.ofPyStrObject:
    size = -1
    return PyErr_BadArgument()
  (utf8, size) = obj.PyStrObject.asUTF8AndSize

# TODO: encoding, errors params
implStrMagic New(tp: PyObject, obj: PyObject):
  # ref: unicode_new -> unicode_new_impl -> PyObject_Str
  PyObject_StrNonNil obj


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

proc findExpanded[A, B](it1: A, it2: B; start=0, stop = it1.len): int{.inline.} =
  uint32.findWithoutMem(it1, it2, start, stop)
iterator findAllExpanded[A, B](it1: A, it2: B, start=0, stop = it1.len): int =
  for i in uint32.findAllWithoutMem(it1, it2, start, stop): yield i

template implMethodGenTargetAndStartStop*(castTarget) {.dirty.} =
    checkArgNum 1, 3
    let le = self.len
    let
      target = castTarget args[0]
      start = args.clampedIndexOptArgAt(1, 0, le)
      stop =  args.clampedIndexOptArgAt(2, le,le)

template asIs(x): untyped = x
template implMethodGenTargetAndStartStop* {.dirty.} =
  bind asIs
  implMethodGenTargetAndStartStop(asIs)

template implMethodGenStrTargetAndStartStop =
  template castToStr(x): untyped = x.castTypeOrRetTE PyStrObject
  implMethodGenTargetAndStartStop castToStr

template doFind(cb): untyped =
  ## helper to avoid too much `...it2, start, stop)` code snippet
  cb(it1, it2, start, stop)

proc substringUnsafe*(self: PyStrObject, start, stop: int): PyStrObject =
  ## `PyUnicode_Substring`
  ##
  ## Nim's `self.substr[start, stop+1]`
  ## 
  ## assert start >= 0 and stop >= 0
  let
    len = self.len
    stop = min(stop, len)

  if start == 0 and stop == len:
    return self  # unchanged
  assert not (start < 0 or stop < 0)
    
  if start >= len or stop < start:
    return newPyAscii()
  if self.isAscii:
    newPyString self.data.asciiStr[start ..< stop]
  else:
    newPyString self.data.unicodeStr[start ..< stop]

proc substring*(self: PyStrObject, start, stop: int, res: var PyStrObject): PyIndexErrorObject =
  if start < 0 or stop < 0:
    return newIndexError newPyAscii "string index out of range"
  res = self.substringUnsafe(start, stop)

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


  implStrMethod index:
    implMethodGenStrTargetAndStartStop
    let res = doKindsWith2It(self.str, target.str):
      doFind find
      doFind findExpanded
      doFind findExpanded
      doFind find
    if res >= 0:
      return newPyInt(res)
    let msg = "substring not found"
    newValueError(newPyAscii msg)

  implStrMethod count:
    implMethodGenStrTargetAndStartStop
    var count: int
    template cntAll(it) =
      for _ in it: count.inc
    doKindsWith2It(self.str, target.str):
      cntAll doFind findAll
      cntAll doFind findAllExpanded
      cntAll doFind findAllExpanded
      cntAll doFind findAll
    newPyInt(count)

implStrMethod find:
  implMethodGenStrTargetAndStartStop
  let res = doKindsWith2It(self.str, target.str):
    doFind find
    doFind findExpanded
    doFind findExpanded
    doFind find
  newPyInt(res)

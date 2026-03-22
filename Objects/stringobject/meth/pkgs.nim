
import std/strformat
import pkg/pystrutils
import std/unicode

import ../../[
  pyobject,
  exceptions,
  stringobject,
  listobject, tupleobject,
  noneobject,
]
import ../private/utils
import pkg/nimpatch/[newUninit, castChar]

proc extendToRuneSeq(self: openArray[char]): seq[Rune] =
  result = newSeqUninit[Rune](self.len)
  for i, c in self: result[i] = Rune c

template gen_startswith(startswith){.dirty.} =
  proc startswith*(self: PyStrObject, prefix: PyStrObject, start = 0, `end` = self.len): bool =
    doKindsWith2It(self.str, prefix.str):
      it1.startswith(it2, start, `end`)
      it1.startswith(it2.extendToRuneSeq, start, `end`)
      return
      it1.startswith(it2, start, `end`)

  proc startswith*(self: PyStrObject, prefix: PyTupleObject, start = 0, `end` = self.len): bool =
    template typeErr =
      raise newException(TypeError, fmt"tuple for {astToStr(startswith)} must only contain str, not {i.typeName:.100s}")
    if self.isAscii:
      for i in prefix:
        if not i.ofPyStrObject: typeErr
        let si = PyStrObject i
        if not si.isAscii: continue
        if self.str.asciiStr.startswith(si.str.asciiStr, start, `end`): return true
    else:
      for i in prefix:
        if not i.ofPyStrObject: typeErr
        let si = PyStrObject i
        if self.str.unicodeStr.startswith(
          if si.isAscii: si.str.asciiStr.extendToRuneSeq
          else: si.str.unicodeStr
          , start, `end`
        ): return true

  proc startswith*(self: PyStrObject, prefix: PyObject, start = 0, `end` = self.len): bool =
    if prefix.ofPyStrObject:
      self.startswith(PyStrObject prefix, start, `end`)
    elif prefix.ofPyTupleObject:
      self.startswith(PyTupleObject prefix, start, `end`)
    else:
      raise newException(TypeError, fmt"{astToStr(startswith)} first arg must be str or a tuple of str, not {prefix.typeName:.100s}")

gen_startswith startswith
gen_startswith endswith

template forAdd(iter, itExpr) =
  for it{.inject.} in iter:
    result.add itExpr

template gen_split(split){.dirty.} =
  proc split*(self: PyStrObject; sep: PyStrObject, maxsplit: int = -1): PyListObject{.raises: [ValueError].} =
    ## `_PyUnicode_Split`
    ## 
    ## raises ValueError if `sep` is empty
    result = newPyList()
    doKindsWith2It(self.str, sep.str):
      forAdd it1.split(it2, maxsplit), newPyStr it
      forAdd it1.split(it2.extendToRuneSeq, maxsplit), newPyStr it
      return
      forAdd it1.split(it2, maxsplit), newPyAscii it


  proc split*(self: PyStrObject; sep: PyNoneObject = pyNone, maxsplit: int = -1): PyListObject =
    ## `_PyUnicode_SplitWhitespace`
    result = newPyList()
    case self.str.ascii
    of true:
      forAdd self.str.asciiStr.split(maxsplit), newPyAscii it
    of false:
      forAdd self.str.unicodeStr.split(maxsplit), newPyStr it

  proc split*(self: PyStrObject; sep: PyObject, maxsplit: int = -1): PyObject{.raises: [].} =
    if sep.isPyNone:
      return self.split(sep=pyNone, maxsplit=maxsplit)
    elif sep.ofPyStrObject:
      retValueErrorAscii self.split(sep=PyStrObject sep, maxsplit=maxsplit)
    else:
      return newTypeError(newPyStr &"must be str or None, not {sep.typeName:.100s}")

gen_split split
gen_split rsplit

proc splitlines*(self: PyStrObject; keepends = false): PyListObject{.raises: [].} =
  ## `_PyUnicode_Splitlines`
  result = newPyList()
  case self.str.ascii
  of true:
    forAdd self.str.asciiStr.splitLines(keepends), newPyAscii it
  of false:
    forAdd self.str.unicodeStr.splitLines(keepends), newPyStr it


template gen_partition(partition){.dirty.} =
  proc partition*(self: PyStrObject; sep: PyStrObject): PyTupleObject{.raises: [ValueError].} =
    ## `PyUnicode_Partition`
    ## 
    ## raises ValueError if `sep` is empty
    template forAdd(iter, itExpr) =
      result = PyTuple_Collect:
        for it{.inject.} in iter:
          itExpr
    doKindsWith2It(self.str, sep.str):
      forAdd it1.partition(it2), newPyStr it
      forAdd it1.partition(it2.extendToRuneSeq), newPyStr it
      return
      forAdd it1.partition(it2), newPyAscii it

gen_partition partition
gen_partition rpartition

template gen_strip(strip){.dirty.} =
  proc strip*(self: PyStrObject): PyStrObject =
    if self.isAscii: newPyAscii self.str.asciiStr.strip()
    else: newPyStr self.str.unicodeStr.strip()

  proc strip*(self, chars: PyStrObject): PyStrObject =
    doKindsWith2It(self.str, chars.str):
      newPyStr it1.strip(it2)
      newPyStr it1.strip(it2.extendToRuneSeq)
      newPyAscii:
        var s: string
        for i in it2:
          if i.ord < 128:
            s.add castChar(cast[uint32](i))
        it1.strip(s)
      newPyAscii it1.strip(it2)

  proc strip*(self: PyStrObject, chars: PyObject): PyObject =
    if chars.isPyNone:
      self.strip()
    elif chars.ofPyStrObject:
      self.strip(PyStrObject chars)
    else:
      newTypeError newPyAscii"strip arg must be str or None"

gen_strip strip
gen_strip lstrip
gen_strip rstrip

proc replace*(self, old, `new`: PyStrObject): PyStrObject =
  if self.isAscii and old.isAscii and `new`.isAscii:
    return newPyAscii self.str.asciiStr.replace(old.str.asciiStr, `new`.str.asciiStr)
  newPyStr self.asUTF8.replace(old.asUTF8, `new`.asUTF8)

proc replace*(self, old, `new`: PyStrObject, count: int): PyStrObject =
  if count == -1:
    return self.replace(old, `new`)
  if self.isAscii and old.isAscii and `new`.isAscii:
    return newPyAscii self.str.asciiStr.replace(old.str.asciiStr, `new`.str.asciiStr, count)
  newPyStr self.asUTF8.replace(old.asUTF8, `new`.asUTF8, count)

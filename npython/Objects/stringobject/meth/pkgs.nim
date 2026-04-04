
import std/strformat
from std/strutils import nil
import pkg/pystrutils
import pkg/unicode_case
import std/unicode except toLower, toUpper, toTitle,
  isAlpha, isDigit, isSpace, isLower, isUpper, isTitle

import ../../[
  pyobject,
  exceptions,
  stringobject,
  listobject, tupleobject,
  noneobject,
  boolobject,
  bltcommon,
]
import ../private/utils
import ../../../Python/getargs/dispatch
import pkg/nimpatch/[newUninit, castChar]

proc toval(obj: PyObject, val: var PyStrObject): PyBaseErrorObject =
  if obj.ofPyStrObject:
    val = PyStrObject obj
    return
  errorIfNotString(obj, "argument must be str")

proc capitalize*(self: PyStrObject): PyStrObject{.clinicGenMethod(str).} =
  if self.isAscii:
    newPyAscii strutils.capitalizeAscii(self.str.asciiStr)
  else:
    newPyStr unicode_case.capitalize(self.str.unicodeStr)

proc casefold*(self: PyStrObject): PyStrObject{.clinicGenMethod(str).} =
  if self.isAscii:
    newPyAscii strutils.toLowerAscii(self.str.asciiStr)
  else:
    newPyStr unicode_case.casefold(self.str.unicodeStr)

proc extendToRuneSeq(self: openArray[char]): seq[Rune] =
  result = newSeqUninit[Rune](self.len)
  for i, c in self: result[i] = Rune c


template gen_adjust(center){.dirty.} =
  proc center*(self: PyStrObject, width: int, fillchar = newPyAscii ' '): PyStrObject{.clinicGenMethodRaises(str, [TypeError]).} =
    doKindsWith2It(self.str, fillchar.str):
      newPyStr it1.center(width, it2)
      newPyStr it1.center(width, it2.extendToRuneSeq)
      newPyStr it1.extendToRuneSeq.center(width, it2)
      newPyAscii it1.center(width, it2)

gen_adjust center
gen_adjust ljust
gen_adjust rjust

proc zfill*(self: PyStrObject, width: int): PyStrObject{.clinicGenMethod(str).} =
  if self.isAscii:
    newPyAscii self.str.asciiStr.zfill(width)
  else:
    newPyStr self.str.unicodeStr.zfill(width)


proc expandtabs[C](a: openArray[C], tabsize=8): seq[C] =
  expandtabsImpl(a, tabsize, a.len, items, newSeqOfCap[C])

proc expandtabs*(self: PyStrObject, tabsize = 8): PyStrObject{.clinicGenMethod(str).} =
  if self.isAscii:
    newPyAscii self.str.asciiStr.expandTabs(tabsize)
  else:
    newPyStr self.str.unicodeStr.expandTabs(tabsize)

#TODO:str
#proc format*(self: PyStrObject, args: varargs[PyObject]): PyStrObject = pyformat
#proc isalnum*(self: PyStrObject): bool{.clinicGenMethod(str).} =

template toval(obj: bool, val: var PyObject): PyBaseErrorObject =
  val = newPyBool obj
  nil

template genPredict(name){.dirty.} =
  proc name*(self: PyStrObject): bool{.clinicGenMethod(str).} =
    if self.isAscii:
      self.str.asciiStr.name()
    else:
      self.str.unicodeStr.name()

genPredict isalpha
#  genPredict isascii  # ref ./meth
#genPredict isdigit
genPredict isdecimal
#genPredict isidentifier
genPredict islower
#genPredict isnumeric
#genPredict isprintable
genPredict isspace
genPredict istitle
genPredict isupper

template genMapper(name; nName: untyped = name){.dirty.} =
  proc name*(self: PyStrObject): PyStrObject{.clinicGenMethod(str).} =
    if self.isAscii:
      newPyAscii self.str.asciiStr.nName()
    else:
      newPyStr self.str.unicodeStr.nName()

genMapper lower, toLower
genMapper upper, toUpper
#genMapper swapcase
genMapper title, toTitle

template gen_removesuffix(removesuffix){.dirty.} =
  proc removesuffix*(self: PyStrObject, suffix: PyStrObject): PyStrObject{.clinicGenMethod(str).} =
    doKindsWith2It(self.str, suffix.str):
      newPyStr it1.removesuffix(it2)
      newPyStr it1.removesuffix(it2.extendToRuneSeq)
      newPyStr it1.extendToRuneSeq.removesuffix(it2)
      newPyAscii it1.removesuffix(it2)

gen_removesuffix removesuffix
gen_removesuffix removeprefix

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

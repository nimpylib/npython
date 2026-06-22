
import std/strutils

include ./comm
impObjects [
  exceptions,
  stringobject,
  listobject,
]
import ../purepaths
import ../paths

template genProp(name; newPy: untyped = newPyStr) {.dirty.} =
  genProperty PurePath, astToStr(name), name, newPy(self.name)

template asIs(x): untyped = x

using self: PyPurePathObject

#TODO:pathlib parents, parts, drive, root, anchor
proc parentStr*(self): string =
  let idx = self.str.rfind(self.getSep())
  if idx < 0: self.str
  else: self.str[0..<idx]
proc parent*(self): PyPurePathObject = self.withPath self.parentStr
genProp parent, asIs


proc suffix*(self): string =
  let idx = self.str.rfind('.')
  if idx < 0: return
  self.str[idx..^1]
#genProperty PurePath, "suffix", suffixObj, newPyStr(self.suffix)
genProp suffix

iterator iterSuffix*(self): string =
  let start = self.str.rfind(self.getSep())

  var idx = self.str.find('.', start+1)
  var pre = idx
  if idx >= 0:
    while true:
      idx = self.str.find('.', idx+1)
      if idx < 0: break
      yield self.str[pre..<idx]
      pre = idx

proc suffixes*(self): seq[PyStrObject] =
  for s in self.iterSuffix: result.add newPyStr s
#genProperty PurePath, "suffix", suffixObj, newPyStr(self.suffix)
genProp suffixes, newPyList

proc getPathName(str: string, sep: char, start=0): string =
  let idx = str.rfind(sep, start)
  if idx < 0: return str[start..^1]
  str[idx + 1 .. ^1]
method name*(self): string {.base, raises: [].} = self.str.getPathName self.getSep()
proc getWinName*(self: PyPurePathObject): string {.raises: [].} =
  if not self.str.startsWith("//"): return self.name
  if self.str.len == 2: return  # '//'

  # skip srv name
  var idx = self.str.find('/', 2)
  if idx < 0: return
  idx.inc

  # skip share name
  idx = self.str.find('/', idx)
  if idx < 0: return
  idx.inc

  getPathName(self.str, self.getSep(), idx)
method name*(self: PyPureWindowsPathObject): string {.raises: [].} = self.getWinName
method name*(self: PyWindowsPathObject): string {.raises: [].} = self.getWinName
#XXX:PY-DIFF: multile inheritance is not supported
genProp name

proc stem*(self): string =
  var sidx = self.str.rfind(self.getSep())
  if sidx < 0: sidx = 0
  var eidx = self.str.rfind('.', sidx)
  if eidx < 0: eidx = self.str.len
  self.str[sidx ..< eidx]
genProp stem  




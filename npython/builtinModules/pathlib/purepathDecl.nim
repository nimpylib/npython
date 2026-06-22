
import std/hashes
export Hash

import ../private/utils
import ../os/funcs/fspathUtils/fspath
export fspath

impObjects [
  pyobject,
  exceptions,
  stringobject,
]

imp Utils, utils

declarePyType PurePath():
  s{.private.}: string
  hash{.private.}: Hash
  hasHash{.private.}: bool

method getSep*(self: PyPurePathObject): char {.base, raises: [].} = unreachable  ## EXT.
proc with_path*(self: PyPurePathObject, s: string): PyPurePathObject{.raises: [].} =
  let pyObjType = self.pyType
  let res = PyPurePathObject pyObjType.tp_alloc(`pyObjType`, 0)
  res.s = s
  return res
proc str*(self: PyPurePathObject): string = self.s

method hashImpl(self: PyPurePathObject): Hash {.base, raises: [].} = hash self.str
method cmpImpl(self, other: PyPurePathObject): int {.base, raises: [].} =
  cmp(self.str, other.str)
template genCmp(`==`) {.dirty.} =
  proc `==`*(self, other: PyPurePathObject): bool = `==`(self.cmpImpl(other), 0)
genCmp `==`
genCmp `<`
genCmp `<=`

proc hash*(self: PyPurePathObject): Hash =
  if self.hasHash:
    return self.hash
  result = self.hashImpl
  self.hash = result
  self.hasHash = true

proc addPart*(res: var string; p: string; sep: char) =
  if res.len > 0 and res[^1] != sep:  # NOTE: DO NOT use `endsWith`
    res.add sep
  res.add p

template partAsStr*(p: PyObject): string =
  if not p.ofPyStrObject:
    return newTypeError newPyStr(
      "argument should be a str or an os.PathLike object " &
      "where __fspath__ returns a str, not '" &
        p.typeName & "'")
  PyStrObject(p).asUTF8

proc init*(self: PyPurePathObject, args: openArray[PyObject]; sep = self.getSep): PyBaseErrorObject =
  ## EXT.
  var res: string
  let sep = self.getSep()
  if args.len == 0:
    self.s = "."
    return
  var p: PyObject
  for i in args:
    retIfExc fspath(i, p)
    res.addPart partAsStr(p), sep
  self.s = res


import std/strutils
include ./comm

impObjects [
  bltcommon,
  exceptions,
  stringobject,
]
import ./props

template genWithX(name) {.dirty.} =
  implPurePathMethod name(other):
    var p: PyObject
    retIfExc fspath(other, p)
    self.name p.partAsStr

using self: PyPurePathObject
proc with_name*(self; name: string): PyPurePathObject =
  let idx = self.str.rfind(self.getSep())
  let res = if idx < 0:
    name
  else:
    self.str[0..idx] & name
  self.with_path res
genWithX with_name

proc with_stem*(self; stem: string): PyPurePathObject =
  self.with_path(
    self.parentStr & self.getSep() & stem & self.suffix
  )
genWithX with_stem

proc with_suffix*(self; suffix: string): PyPurePathObject =
  let idx = self.str.rfind('.')
  self.with_path (
    if idx < 0: self.str
    else: self.str[0..<idx]
  ) & suffix

genWithX with_suffix

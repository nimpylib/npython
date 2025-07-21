
import std/hashes
import std/unicode
export Rune, unicode.`==`, toRunes
from std/strutils import join
import macros

import pyobject

type UnicodeVariant* = ref object
  ## UCS1 or UCS4 variant
  setHash*: bool
  hash*: Hash
  case ascii*: bool
  of true: 
    asciiStr*: string
  of false:
    unicodeStr*: seq[Rune]

template doBothKindOk*(self: UnicodeVariant, op): untyped =
  case self.ascii:
  of true: op self.asciiStr
  of false: op self.unicodeStr

proc `$`*(self: UnicodeVariant): string =
  doBothKindOk(self, `$`)


proc newAsciiUnicodeVariant*(s: string): UnicodeVariant =
  UnicodeVariant(ascii: true, asciiStr: s)
proc newAsciiUnicodeVariant*(s: seq[char]): UnicodeVariant =
  UnicodeVariant(ascii: true, asciiStr: s.join)

proc newUnicodeUnicodeVariant*(s: seq[Rune]): UnicodeVariant =
  UnicodeVariant(ascii: false, unicodeStr: s)
proc newUnicodeUnicodeVariant*(s: string): UnicodeVariant =
  newUnicodeUnicodeVariant s.toRunes
proc newUnicodeUnicodeVariantOfCap*(cap: int): UnicodeVariant =
  newUnicodeUnicodeVariant(newSeqOfCap[Rune](cap))

proc newAsciiUnicodeVariantOfCap*(cap: int): UnicodeVariant =
  newAsciiUnicodeVariant(newStringOfCap(cap))

proc newUnicodeVariant*(s: string, ensureAscii = false): UnicodeVariant =
  ## Create a new `UnicodeVariant` object.
  if ensureAscii:
    UnicodeVariant(ascii: true, asciiStr: s)
  else:
    UnicodeVariant(ascii: false, unicodeStr: s.toRunes)

template add(r: seq[Rune], s: openArray[char]) =
  let oldLen = r.len
  r.setLen(r.len + s.len)
  for i in 0..<s.len:
    r[oldLen + i] = Rune s[i]

template cat[A, B](a: openArray[A], b: openArray[B]): seq[Rune] =
  var s = newSeqOfCap[Rune](a.len + b.len)
  s.add(a)
  s.add(b)
  s

proc `&`*(a, b: UnicodeVariant): UnicodeVariant =
  case (a.ascii.uint8 shl 1) or b.ascii.uint8
  of 0:
    newUnicodeUnicodeVariant(a.unicodeStr & b.unicodeStr)
  of 1:
    newUnicodeUnicodeVariant(cat(a.unicodeStr, b.asciiStr))
  of 2:
    newUnicodeUnicodeVariant(cat(a.asciiStr, b.unicodeStr))
  else: # of 3
    newAsciiUnicodeVariant(a.asciiStr & b.asciiStr)

proc asRuneSeq(self: string): seq[Rune] =
  result = (when declared(newSeqUninit): newSeqUninit else: newSeq)[Rune](self.len)
  for i, c in self: result[i] = Rune c

proc toRunes*(self: UnicodeVariant): seq[Rune] =
  if self.ascii: self.asciiStr.asRuneSeq
  else: self.unicodeStr


template add*(r: seq[Rune], c: char) = r.add Rune c
proc joinAsRunes*(r: openArray[UnicodeVariant], sep: string): seq[Rune] =
  ## Join `UnicodeVariant` with a separator.
  result = newSeqOfCap[Rune](r.len)
  if r.len == 0:
    return
  result.add r[0].toRunes
  for i in 1..<r.len:
    result.add sep.toRunes
    result.add r[i].toRunes

proc hashImpl(self: UnicodeVariant): Hash {. inline, cdecl .} = 
  result = Hash 0
  template forLoop(ls) =
    for i in ls:
      result = result !& hash(cast[uint32](i))
  if self.ascii:
    forLoop self.asciiStr
  else:
    forLoop self.unicodeStr
  result = !$result

proc hash*(self: UnicodeVariant): Hash {. inline, cdecl .} = 
  #self.str.doBothKindOk hash
  # XXX: do not use `doBothKindOk` here,
  # as hash(s.toRunes) is not equal to hash(s)
  if self.setHash:  # Updated to use self directly
    return self.hash
  result = hashImpl(self)  # Ensure to return the hash value
  self.hash = result
  self.setHash = true


proc `==`*(self, other: UnicodeVariant): bool {. inline, cdecl .} =
  template cmpAttr(a, b) =
    if self.a.len > other.b.len: return false
    for i, c in self.a:
      if uint32(c) != uint32(other.b[i]):
        return false
    return true

  case ((self.ascii.uint8 shl 1) or other.ascii.uint8)
  of 0:
    return self.unicodeStr == other.unicodeStr
  of 1:
    cmpAttr(unicodeStr, asciiStr)
  of 2:
    cmpAttr(asciiStr, unicodeStr)
  else: # of 3
    return self.asciiStr == other.asciiStr


declarePyType Str(tpToken):
  str: UnicodeVariant

proc `==`*(self, other: PyStrObject): bool {. inline, cdecl .} =
  self.str == other.str

proc hash*(self: PyStrObject): Hash {. inline, cdecl .} =
  result = hash(self.str) # don't write as self.str.hash as that returns attr

method `$`*(strObj: PyStrObject): string =
  $strObj.str

proc repr*(strObj: PyStrObject): string =
  '\'' & $strObj.str & '\''   # TODO

proc newPyString*(str: UnicodeVariant): PyStrObject{.inline.} =
  result = newPyStrSimple()
  result.str = str

proc newPyString*(str: string, ensureAscii=false): PyStrObject =
  newPyString str.newUnicodeVariant(ensureAscii)
proc newPyString*(str: seq[Rune]): PyStrObject =
  newPyString newUnicodeUnicodeVariant(str)
proc newPyAscii*(str: string): PyStrObject =
  newPyString newAsciiUnicodeVariant(str)

# TODO: make them faster
proc newPyString*(r: Rune): PyStrObject{.inline.} = newPyString @[r]
proc newPyString*(c: char): PyStrObject{.inline.} = newPyString $c

proc `&`*(self: PyStrObject, i: PyStrObject): PyStrObject {. cdecl .} =
  newPyString self.str & i.str

proc len*(strObj: PyStrObject): int {. inline, cdecl .} =
  strObj.str.doBothKindOk(len)

template newPyStr*(s: string; ensureAscii=false): PyStrObject =
  bind newPyString
  newPyString(s, ensureAscii)
template newPyStr*(s: seq[Rune]|UnicodeVariant): PyStrObject =
  bind newPyString
  newPyString(s)

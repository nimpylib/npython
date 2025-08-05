
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

macro doKindsWith2It*(self, other: UnicodeVariant, do0_3): untyped =
  result = nnkCaseStmt.newTree(quote do:
    ((`self`.ascii.uint8 shl 1) or `other`.ascii.uint8)
  )
  do0_3.expectLen 4
  template alias(name, val): NimNode =
    newProc(name, @[ident"untyped"], val, procType=nnkTemplateDef)
  template ofI(i: int, attr1, attr2) =
    let iNode = newIntLitNode(i)
    let doSth = do0_3[i]
    var ofStmt = nnkOfBranch.newTree iNode
    var blk = newStmtList()
    blk.add alias(ident"it1", self.newDotExpr(attr1))
    blk.add alias(ident"it2", other.newDotExpr(attr2))
    blk.add doSth
    ofStmt.add blk
    result.add ofStmt
  let
    u = ident"unicodeStr"
    a = ident"asciiStr"
  ofI 0, u, u
  ofI 1, u, a
  ofI 2, a, u
  ofI 3, a, a
  result.add nnkElse.newTree(
    quote do: raiseAssert"unreachable"
  )


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
    if a.len > b.len: return false
    for i, c in a:
      if uint32(c) != uint32(b[i]):
        return false
    return true

  doKindsWith2It(self, other):
    return it1 == it2
    cmpAttr(it1, it2)
    cmpAttr(it1, it2)
    return it1 == it2

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
let empty = newPyAscii""
proc newPyAscii*(): PyStrObject = empty  ## empty string

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

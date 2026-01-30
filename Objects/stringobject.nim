
import ./hash_def
import std/unicode
export Rune, unicode.`==`, toRunes, `<%`, `>%`
from std/strutils import join
import std/macros

import pkg/pyrepr

import ./pyobject
import ../Utils/[castChar, addr0,]

type UnicodeVariant* = ref object
  ## UCS1 or UCS4 variant
  setHash*: bool
  hash*: Hash
  case ascii*: bool
  of true: 
    asciiStr*: string
  of false:
    unicodeStr*: seq[Rune]  ## maxchar cannot below high(char)

template doBothKindOk*(self: UnicodeVariant, op): untyped =
  case self.ascii:
  of true: op self.asciiStr
  of false: op self.unicodeStr

proc `$`*(self: UnicodeVariant): string =
  doBothKindOk(self, `$`)


proc newAsciiUnicodeVariant*(s: string|cstring|char): UnicodeVariant =
  UnicodeVariant(ascii: true, asciiStr: $s)
proc newAsciiUnicodeVariant*(s: seq[char]): UnicodeVariant =
  UnicodeVariant(ascii: true, asciiStr: s.join)

proc newUnicodeUnicodeVariant*(s: seq[Rune]): UnicodeVariant =
  UnicodeVariant(ascii: false, unicodeStr: s)

const hasCStringOA = compiles(block:
  var s: cstring
  s.toOpenArray(0, 0)
)
template toFullOpenArrayChar(s): untyped =
  when hasCStringOA: s.toOpenArray(0, s.high)
  else: $s  #JS

proc newUnicodeUnicodeVariant*(s: cstring): UnicodeVariant = newUnicodeUnicodeVariant(
  s.toFullOpenArrayChar.toRunes
)
proc newUnicodeUnicodeVariant*(s: string): UnicodeVariant = newUnicodeUnicodeVariant s.toRunes
proc newUnicodeUnicodeVariantOfCap*(cap: int): UnicodeVariant =
  newUnicodeUnicodeVariant(newSeqOfCap[Rune](cap))

proc newUnicodeOrAsciiUnicodeVariant*(s: string|cstring): UnicodeVariant =
  var ascii = true
  for r in s.toFullOpenArrayChar.runes:
    if Rune(high char) <% r:
      ascii = false
      break
  if ascii: newAsciiUnicodeVariant(s)
  else: newUnicodeUnicodeVariant(s)

proc newAsciiUnicodeVariantOfCap*(cap: int): UnicodeVariant =
  newAsciiUnicodeVariant(newStringOfCap(cap))

proc newUnicodeVariant*(c: char): UnicodeVariant = newAsciiUnicodeVariant c
proc newUnicodeVariant*(c: Rune): UnicodeVariant = newUnicodeUnicodeVariant @[c]
proc newUnicodeVariant*(s: string|cstring, ensureAscii = false): UnicodeVariant =
  ## Create a new `UnicodeVariant` object.
  if ensureAscii:
    UnicodeVariant(ascii: true, asciiStr: $s)
  else:
    #UnicodeVariant(ascii: false, unicodeStr: ($s).toRunes)
    newUnicodeOrAsciiUnicodeVariant(s)

proc newUnicodeVariant*(len: int, isAscii = false): UnicodeVariant =
  if isAscii:
    UnicodeVariant(ascii: true, asciiStr: (when declared(newStringUninit): newStringUninit else: newString)(len))
  else:
    UnicodeVariant(ascii: false, unicodeStr: (when declared(newSeqUninit): newSeqUninit else: newSeq)[Rune](len))

proc newUnicodeVariant*(s: openArray[char], ensureAscii = false): UnicodeVariant =
  let L = s.len
  var str = (when declared(newStringUninit): newStringUninit else: newString)(L)
  when declared(copyMem):
    copyMem(str.addr0, s.addr0, L)
  else:
    for i, c in s: str[i] = c
  newUnicodeVariant(str, ensureAscii)


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

proc `&`*(a, b: UnicodeVariant): UnicodeVariant =
  doKindsWith2It(a, b):
    newUnicodeUnicodeVariant(it1 & it2)
    newUnicodeUnicodeVariant(cat(it1, it2))
    newUnicodeUnicodeVariant(cat(it1, it2))
    newAsciiUnicodeVariant(it1 & it2)
template add*(r: seq[Rune], c: char) = r.add Rune c
proc `&`*(a: UnicodeVariant, c: char): UnicodeVariant =
  if a.ascii: a.asciiStr.add c
  else: a.unicodeStr.add c

proc len*(str: UnicodeVariant): int {. cdecl .} =
  str.doBothKindOk(len)

proc joinAsRunes*(r: openArray[UnicodeVariant], sep: string): seq[Rune] =
  ## Join `UnicodeVariant` with a separator.
  result = newSeqOfCap[Rune](r.len)
  if r.len == 0:
    return
  result.add r[0].toRunes
  for i in 1..<r.len:
    result.add sep.toRunes
    result.add r[i].toRunes

template itemSize*(self: UnicodeVariant): int =
  ## returns 1 or 4 currently
  if self.ascii: 1 else: 4

proc hashImpl(self: UnicodeVariant): Hash {. inline, cdecl .} = 
  template forLoop(ls): untyped =
    Py_HashBuffer(ls)
  if self.ascii:
    forLoop self.asciiStr
  else:
    forLoop self.unicodeStr

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

proc cmpAscii*(self: PyStrObject; s: string): int =
  ## PyUnicode_CompareWithASCIIString
  if self.str.ascii: return cmp(self.str.asciiStr, s)
  else:
    result = cmp(self.str.unicodeStr.len, s.len)
    template loopCmp(eachPreDo){.dirty.} =
      for i, rune in self.str.unicodeStr:
        eachPredo
        let rsi = Rune s[i]
        if rune != rsi:
          return (if rune <% rsi: -1 else: 1)
    if result <= 0:
      loopCmp: discard
    else:
      loopCmp:
        if i > s.high:
          return 1
    # then return result

proc eqAscii*(self: PyStrObject; s: string): bool =
  ## `_PyUnicode_EqualToASCIIString`
  self.cmpAscii(s) == 0

template itemSize*(self: PyStrObject): int =
  ## `PyUnicode_KIND`
  self.str.itemSize

proc hash*(self: PyStrObject): Hash {. inline, cdecl .} =
  result = hash(self.str) # don't write as self.str.hash as that returns attr

method `$`*(strObj: PyStrObject): string{.raises: [].} =
  $strObj.str

proc repr*(strObj: PyStrObject): string =
  pyrepr $strObj.str

proc newPyString*(str: UnicodeVariant): PyStrObject{.inline.} =
  result = newPyStrSimple()
  result.str = str

proc newPyString*(str: string|cstring|openArray[char]|int, ensureAscii=false): PyStrObject =
  newPyString str.newUnicodeVariant(ensureAscii)
proc newPyString*(str: seq[Rune]): PyStrObject =
  newPyString newUnicodeUnicodeVariant(str)
proc newPyString*(str: PyStrObject): PyStrObject{.cdecl, inline.} =
  ## helper for handle type of `string|PyStrObject`
  str

proc newPyAscii*(str: string|cstring|char|int): PyStrObject =
  newPyString newAsciiUnicodeVariant(str)
let empty = newPyAscii""
proc newPyAscii*(): PyStrObject = empty  ## empty string

proc newPyString*(c: char|Rune): PyStrObject = newPyString newUnicodeVariant(c)

proc `&`*(self: PyStrObject, i: PyStrObject): PyStrObject {. cdecl .} =
  newPyString self.str & i.str
proc `&`*(self: PyStrObject, c: char): PyStrObject {. cdecl .} = newPyString self.str & c

proc len*(strObj: PyStrObject): int {. inline, cdecl .} = strObj.str.len

template newPyStr*(s: string|cstring|openArray[char]|int; ensureAscii=false): PyStrObject =
  bind newPyString
  newPyString(s, ensureAscii)
template newPyStr*(s: seq[Rune]|UnicodeVariant|PyStrObject|char|Rune): PyStrObject =
  bind newPyString
  newPyString(s)

template asUTF8byret =
  if self.ascii: ret self.asciiStr
  else:
    let s = $self.unicodeStr
    ret s

proc asUTF8*(self: UnicodeVariant): string =
  template ret(s) = return s
  asUTF8byret

proc asUTF8AndSize*(self: UnicodeVariant): tuple[utf8: string, size: int] =
  template ret(s) = return (s, s.len)
  asUTF8byret

proc asUTF8AndSize*(self: PyStrObject): tuple[utf8: string, size: int] =
  ## PyUnicode_AsUTF8AndSize
  self.str.asUTF8AndSize

proc asUTF8*(self: PyStrObject): string =
  ## PyUnicode_AsUTF8
  self.str.asUTF8

template data*(self: PyStrObject): UnicodeVariant =
  ## restype is unstable.
  self.str
template kind*(self: PyStrObject): bool =
  ## restype is unstable.
  self.str.ascii
proc PyUnicode_READ*(kind: bool, data: UnicodeVariant, index: int): Rune{.inline.} =
  case kind
  of true: data.asciiStr[index].Rune
  of false: data.unicodeStr[index]

proc `[]`*(self: PyStrObject, index: int): Rune{.inline.} =
  ## helper for `PyUnicode_READ`
  PyUnicode_READ(self.kind, self.data, index)

proc isAscii*(self: PyStrObject): bool {.inline.} =
  ## `PyUnicode_IS_ASCII`
  self.str.ascii

const MAX_UNICODE* = 0x10ffff

proc checkConsistency*(self: PyStrObject, check_content: static[bool] = false): bool =
  ## `_PyUnicode_CheckConsistency`
  template CHECK(b) =
    #PyObject_ASSERT_FAILED_MSG
    if not b: assert false, astToStr(b)
  when check_content:
    var maxchar = Rune 0
    for c in self:
      if c > maxchar: maxchar = c
    case self.itemSize
    of 1: CHECK maxchar in 0..255
    of 4: CHECK maxchar in 255..MAX_UNICODE
    else: unreachable
  true

proc copy_characters(dest: PyStrObject, dest_start: int, frm: PyStrObject, frm_start: int,
    how_many: int, check_maxchar: static[bool]): bool =
  ## returns if failed due to maxchar check
  assert dest.len - dest_start >= how_many
  assert frm.len - frm_start >= how_many
  let
    to_kind = dest.itemSize
    from_kind = frm.itemSize
  if from_kind == to_kind:
    when declared(copyMem):
      let itemSize = dest.itemSize
      template copyImpl(dest, dest_start, frm, frm_start, how_many) =
        copyMem(dest[dest_start].addr, frm[frm_start].addr, itemSize * how_many)
      template gen(fld){.dirty.} =
        template `copy fld` =
          copyImpl(dest.str.fld, dest_start, frm.str.fld, frm_start, how_many)
      gen asciiStr
      gen unicodeStr
      if to_kind == 1: copyasciiStr
      else: copyunicodeStr
      return
  assert to_kind >= from_kind

  var it: Rune
  template loopAsgn(destData, doIt){.dirty.} =
    for i in 0..<how_many:
      it = frm[frm_start + i]
      destData[dest_start + i] = doIt
  if dest.isAscii:
    loopAsgn dest.str.asciiStr:
      if it >% Rune(255):
        when check_maxchar: return true
        else: castChar(it)
      else:
        cast[char](it)
  else:
    loopAsgn dest.str.unicodeStr, it


proc fastCopyCharacters*(dest: PyStrObject, dest_start: int, frm: PyStrObject, frm_start: int = 0,
    how_many: int = frm.len - frm_start) =
  ## `_PyUnicode_FastCopyCharacters`
  discard copy_characters(dest, dest_start, frm, frm_start, how_many, false)

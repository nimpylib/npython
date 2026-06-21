
import std/unicode
from std/strutils import toHex
import pkg/handy_sugars/backendMark

include ./comm
impObjects [
  exceptions,
]
when ucs2:
  imp Utils, utils
  #import std/widestrs
  # std/widestrs lacks `Runes -> ptr wchar_t` conversion, so we implement it ourselves here
  type Utf16Char = wchar_t

template toWchar*(rune: Rune): wchar_t =
  when ucs2:
    if rune > high wchar_t:
      let unicodeEscapeContent = rune.ord.toHex(8)
      return newTypeError newPyAscii(
        r"the string '\U" & 
          unicodeEscapeContent & "' cannot be converted to a single wchar_t character"
      )
  cast[wchar_t](rune)

type WideCString = ptr wchar_t

when ucs2:
  proc toAllocedWideCString(source: openArray[Rune], result: var WideCString) =
    var d = 0
    for r in sources:
      let ch = cast[uint32](r)
      if ch <= UNI_MAX_BMP:
        if ch >= UNI_SUR_HIGH_START and ch <= UNI_SUR_LOW_END:
          result[d] = UNI_REPLACEMENT_CHAR
        else:
          result[d] = cast[Utf16Char](ch)
      elif ch > UNI_MAX_UTF16:
        #result[d] = UNI_REPLACEMENT_CHAR
        unreachable
      else:
        let ch = ch - halfBase
        result[d] = cast[Utf16Char](uint16((ch shr halfShift) + UNI_SUR_HIGH_START))
        inc d
        result[d] = cast[Utf16Char](uint16((ch and halfMask) + UNI_SUR_LOW_START))
      inc d
    result[d] = Utf16Char(0)


template newWStr(L: int): untyped =
  cast[WideCString](alloc (L+1) * sizeof(wchar_t))

proc asWideCharString*(x: PyStrObject; size: var int): WideCString{.noWeirdBackend, npyexportc: "PyUnicode_AsWideCharString".} =
  let L = x.len
  result = newWStr L
  when ucs2:
    if x.isAscii:
      for i, r in x.pairs:
        result[i] = cast[wchar_t](r)
    else:
      let extraN = x.str.unicodeStr.countIt it %> Rune UNI_MAX_BMP
      if extraN != 0:
        let nSize = L + 1 + extraN
        result = realloc(result, nSize * sizeof(wchar_t))
      toAllocedWideCString(x.str.unicodeStr, result)

  else:
    for i, r in x.pairs:
      result[i] = r.toWchar
  result[L] = wchar_t(0)
  size = L

proc toAllocedWideCString*(x: PyStrObject): WideCString {.noWeirdBackend.} =
  var unused: int
  asWideCharString(x, unused)


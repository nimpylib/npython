
import std/strformat
include ./comm

proc newPyStr*(c: wchar_t): PyObject =
  newPyStr @[Rune c]

template newPyStrFromWChars(L: int; chars): PyStrObject =
  case L
  of 0:
    return newPyAscii()
  of 1:
    return newPyStr s[0]
  else: discard
  # NOTE: following `when ucs2` assumes `s`.len > 1

  var allAscii = true

  for i in chars:
    if i > wchar_t(255):
      allAscii = false
      break

  template asgn(char): untyped {.dirty.} =
    var ls = newSeq[char](L)
    for i in 0..<L:
      let w = s[i]
      ls[i] = cast[char](w)
    newPyStr ls
  if allAscii: asgn char
  else:
    when ucs2:
      var ls = newSeq[Rune](L)
      var lsI = 0
      assert L >= 2  # 0 handled above, so this is just to satisfy the compiler
      var i = 0
      while i < L:
        var ch = ord(s[i])
        inc i
        if i < L and ch >= UNI_SUR_HIGH_START and ch <= UNI_SUR_HIGH_END:
          # If the 16 bits following the high surrogate are in the source buffer...
          let ch2 = ord(s[i])

          # If it's a low surrogate, convert to UTF32:
          if ch2 >= UNI_SUR_LOW_START and ch2 <= UNI_SUR_LOW_END:
            ch = (((ch and halfMask) shl halfShift) + (ch2 and halfMask)) + halfBase
            inc i
          #[else:
          #XXX:BAD-PY: CPython ignores an unpaired high surrogate
            #invalid UTF-16
            ch = replacement
          ]#
        #[
        #XXX:BAD-PY: CPython ignores an unpaired high surrogate
        elif ch >= UNI_SUR_LOW_START and ch <= UNI_SUR_LOW_END:
          #invalid UTF-16
          ch = replacement
        ]#
        
        if ch > MAX_UNICODE_val:
          return newValueError newPyAscii fmt"character U+{ch:x} is not in range [U+0000; U+{MAX_UNICODE:x}]"

        ls[lsI] = cast[Rune](ch)
        lsI.inc
      newPyStr ls
    else:
      asgn Rune

proc newPyStr*(s: openArray[wchar_t]): PyObject{.npyexportc: "PyUnicode_FromWideChar".} =
  ## like `PyUnicode_FromWideChar`, but 
  newPyStrFromWChars(s.len, s)

proc newPyStr*(s: ptr wchar_t): PyObject{.npyexportc: "PyUnicode_FromWideCharNullEnd".} =
  var L = 0
  iterator chars(s: ptr wchar_t): wchar_t =
    while true:
      let i = s[L]
      if i == wchar_t(0):
        break
      L.inc
      yield i
  newPyStrFromWChars(L, s.chars)

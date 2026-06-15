
import pkg/py_locale_utf8_encoding/wchar_t as wcharLib
import ../private/[utils]
impObjects [
  pyobject,
  stringobject,
]

proc newPyStr*(c: wchar_t): PyObject =
  newPyStr @[Rune c]

template newPyStrFromWChars(L: int; chars): PyStrObject =
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
  else: asgn Rune

proc newPyStr*(s: openArray[wchar_t]): PyStrObject =
  newPyStrFromWChars(s.len, s)

proc newPyStr*(s: ptr wchar_t): PyStrObject =
  var L = 0
  iterator chars(s: ptr wchar_t): wchar_t =
    while true:
      let i = s[L]
      if i == wchar_t(0):
        break
      L.inc
      yield i
  newPyStrFromWChars(L, s.chars)

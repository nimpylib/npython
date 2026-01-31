
when defined(nimPreviewSlimSystem):
  import std/assertions
  export assertions

include ./common_h
proc unicode_char(c: uint32): PyObject =
  assert c <= MAX_UNICODE
  newPyStr if c < 256: newAsciiUnicodeVariant cast[char](c)
  else: newUnicodeUnicodeVariant @[cast[Rune](c)]

template retChrOutOfRange =
  return newValueError newPyAscii"chr() arg not in range(0x110000)"
template chkUpperBound =
  if ordinal > MAX_UNICODE: retChrOutOfRange
proc PyUnicode_FromOrdinal*(ordinal: uint32): PyObject =
  chkUpperBound
  unicode_char ordinal

proc PyUnicode_FromOrdinal*(ordinal: int32): PyObject =
  if ordinal < 0: retChrOutOfRange
  PyUnicode_FromOrdinal cast[uint32](ordinal)

proc PyUnicode_FromOrdinal*(ordinal: int): PyObject =
  chkUpperBound
  unicode_char cast[uint32](ordinal)

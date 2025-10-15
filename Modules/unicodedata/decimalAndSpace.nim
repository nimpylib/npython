

from std/unicode import `<%`
include ./common_h
import ./[rune_decl, decimal, space]
import ../../Utils/castChar

const AsciiDigits = "0123456789"
proc transformDecimalAndSpaceToASCII*(unicodeStr: openArray[Rune]): string =
  result = (when declared(newStringUninit): newStringUninit else: newString)(unicodeStr.len)
  for i, rune in unicodeStr:
    template st(val) = result[i] = val
    if rune <% Rune(127): st castChar(rune)
    elif rune.isspace(): st ' '
    else:
      decimalItOr(rune):
        st AsciiDigits[it]
      do:
        st '?'

proc transformDecimalAndSpaceToASCII*(unicode: PyStrObject): string =
  if unicode.isAscii: unicode.str.asciiStr
  else: unicode.str.unicodeStr.transformDecimalAndSpaceToASCII

proc PyUnicode_TransformDecimalAndSpaceToASCII*(unicode: PyStrObject): PyObject =
  ##[ `_PyUnicode_TransformDecimalAndSpaceToASCII`

  Converts a Unicode object holding a decimal value to an ASCII string
for using in int, float and complex parsers.
Transforms code points that have decimal digit property to the
corresponding ASCII digit code points. Transforms spaces to ASCII.
Transforms code points starting from the first non-ASCII code point that
is neither a decimal digit nor a space to the end into '?'.
  ]##
  if unicode.isAscii: unicode
  else: newPyAscii unicode.transformDecimalAndSpaceToASCII

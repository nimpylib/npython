

include ./common_h
import pkg/unicode_space_decimal/decimalAndSpace
export decimalAndSpace

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


import ../private/imp_utils
import pkg/handy_sugars/backendMark
import ./utils

imp Utils, nexportc
impObjects [
  pyobject,
  stringobject,
]
import pkg/py_locale_utf8_encoding/wchar_t as wcharLib
const ucs2 = sizeof(wchar_t) == 2

type WideCString = ptr wchar_t
when ucs2:
  #copied from nim-lang/Nim:std/widestr.nim when v2.3.1
  # with some modifications to fit our needs
  const
    UNI_REPLACEMENT_CHAR = Utf16Char(0xFFFD'i16)
    UNI_MAX_BMP = 0x0000FFFF
    UNI_MAX_UTF16 = 0x0010FFFF
    # UNI_MAX_UTF32 = 0x7FFFFFFF
    # UNI_MAX_LEGAL_UTF32 = 0x0010FFFF

    halfShift = 10
    halfBase = 0x0010000
    halfMask = 0x3FF

    UNI_SUR_HIGH_START = 0xD800
    UNI_SUR_HIGH_END = 0xDBFF
    UNI_SUR_LOW_START = 0xDC00
    UNI_SUR_LOW_END = 0xDFFF
    UNI_REPL = 0xFFFD



from std/math import isNaN

from std/strutils import repeat, toHex, toLowerAscii
from std/unicode import toUTF8
import ../private/utils

from pkg/intobject import `$`

impObjects [
  pyobject,
  exceptions,
  stringobject,
  boolobject,
  noneobject,
  numobjects,
]
imp Python, getargs/tovals

import ./optionsDecl
export optionsDecl

proc addUnicodeEscape(output: var string, codepoint: int) =
  template addHex(value: int) =
    output.add "\\u"
    output.add toHex(value, 4).toLowerAscii
  if codepoint <= 0xffff:
    addHex codepoint
  else:
    let value = codepoint - 0x10000
    addHex(0xd800 + (value shr 10))
    addHex(0xdc00 + (value and 0x3ff))

proc encodeString*(value: PyStrObject, ensureAscii: bool): string =
  result.add '"'
  for rune in value.str:
    let codepoint = int(rune)
    case codepoint
    of int('"'): result.add "\\\""
    of int('\\'): result.add "\\\\"
    of 8: result.add "\\b"
    of 9: result.add "\\t"
    of 10: result.add "\\n"
    of 12: result.add "\\f"
    of 13: result.add "\\r"
    of 0..7, 11, 14..31:
      result.add "\\u"
      result.add toHex(codepoint, 4).toLowerAscii
    else:
      if ensureAscii and codepoint > 0x7f:
        result.addUnicodeEscape codepoint
      else:
        result.add rune.toUTF8
  result.add '"'

proc floatToken*(value: float, allowNan: bool,
                output: var string): PyBaseErrorObject =
  proc oorVE(r: string): auto{.cdecl.} =
    return newValueError newPyAscii(
      "Out of range float values are not JSON compliant: " & r)
  template checkAllowNan(r) =
    if not allowNan: return oorVE(r)

  output.add if value.isNaN:
    checkAllowNan "nan"
    "NaN"
  elif value == Inf:
    checkAllowNan "inf"
    "Infinity"
  elif value == NegInf:
    checkAllowNan "-inf"
    "-Infinity"
  else:
    $value

proc resolveFormatting*(opt: EncodeOptions, itemSeparator, keySeparator,
                       indentUnit: var string,
                       indented: var bool): PyBaseErrorObject =
  indented = not opt.indent.isPyNone
  if indented:
    itemSeparator = ","
    if opt.indent.ofPyStrObject:
      indentUnit = PyStrObject(opt.indent).asUTF8
    elif opt.indent.ofPyBoolObject:
      if PyBoolObject(opt.indent).b:
        indentUnit = " "
    elif opt.indent.ofPyIntObject:
      var width: int
      retIfExc toval(opt.indent, width)
      if width > 0:
        indentUnit = ' '.repeat(width)
    else:
      return newTypeError newPyAscii(
        "indent must be None, int or str")
  else:
    itemSeparator = ", "
  keySeparator = ": "

  if opt.separators.isSome:
    (itemSeparator, keySeparator) = opt.separators.unsafeGet()

proc addIndent*(output: var string, indentUnit: string, depth: int) =
  output.add '\n'
  output.add indentUnit.repeat(depth)

proc pushMarker*(obj: PyObject, checkCircular: bool,
                markers: var seq[PyObject]): PyBaseErrorObject =
  if not checkCircular:
    return
  for marker in markers:
    if Py_IS(marker, obj):
      return newValueError newPyAscii "Circular reference detected"
  markers.add obj

proc encodeKey*(key: PyObject, opt: EncodeOptions,
               output: var string): PyBaseErrorObject =
  if key.ofPyStrObject:
    output.add encodeString(PyStrObject(key), opt.ensure_ascii)
    return

  var value = ""
  if key.ofPyBoolObject:
    value = if PyBoolObject(key).b: "true" else: "false"
  elif key.isPyNone:
    value = "null"
  elif key.ofPyIntObject:
    value = $PyIntObject(key).v
  elif key.ofPyFloatObject:
    retIfExc floatToken(PyFloatObject(key).v, opt.allow_nan, value)
  elif opt.skipkeys:
    return
  else:
    return newTypeError newPyAscii(
      "keys must be str, int, float or None, not " & key.typeName)
  output.add encodeString(newPyAscii(value), opt.ensure_ascii)

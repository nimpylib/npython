
import ../stringobject/fstring
import ./floatobject/toval
import ./numobjects_comm
import ./intobject/magicNew
import ./intobject
import ../../Python/getargs

methodMacroTmpl(Int)

template check_binop: untyped{.dirty.} = 
  if not selfNoCast.ofPyIntObject or not other.ofPyIntObject: return pyNotImplemented
  let self = PyIntObject selfNoCast
template check_binop_do(op): untyped =
  check_binop
  op(self, PyIntObject(other))
template intBinaryTemplate(op, methodName: untyped, methodNameStr:string) = 
  result = check_binop_do(op)

implIntMagic add, [noSelfCast]:
  intBinaryTemplate(`+`, add, "+")


implIntMagic sub, [noSelfCast]:
  intBinaryTemplate(`-`, sub, "-")


implIntMagic mul, [noSelfCast]:
  intBinaryTemplate(`*`, mul, "*")


implIntMagic trueDiv, [noSelfCast]:
  check_binop
  let casted = newPyFloat(self) ## XXX: TODO: ref long_true_divide
  casted.callMagic(trueDiv, other)


implIntMagic floorDiv, [noSelfCast]: check_binop_do(`//`)

implIntMagic Mod, [noSelfCast]:
  intBinaryTemplate(`%`, Mod, "%")

implIntMagic pow, [noSelfCast]:
  intBinaryTemplate(pow, pow, "**")

implIntMagic abs: abs self
implIntMagic And, [noSelfCast]: check_binop_do(`and`)
implIntMagic Or, [noSelfCast]: check_binop_do(`or`)
implIntMagic Xor, [noSelfCast]: check_binop_do(`xor`)
implIntMagic lshift, [noSelfCast]: check_binop_do(`shl`)
implIntMagic rshift, [noSelfCast]: check_binop_do(`shr`)
implIntMagic invert: not self
implIntMagic positive: self
implIntMagic negative: -self

implIntMagic bool: newPyBool not self.zero

implIntMagic lt:
  if other.ofPyIntObject:
    if self < PyIntObject(other):
      result = pyTrueObj
    else:
      result = pyFalseObj
  elif other.ofPyFloatObject:
    result = other.callMagic(ge, self)
  else:
    let msg = fmt"< not supported by int and {other.pyType.name}"
    result = newTypeError(newPyStr msg)


implIntMagic eq:
  if other.ofPyIntObject:
    if self == PyIntObject(other):
      result = pyTrueObj
    else:
      result = pyFalseObj
  elif other.ofPyFloatObject:
    result = other.callMagic(eq, self)
  elif other.ofPyBoolObject:
    if self == pyIntOne:
      result = other
    else:
      result = other.callMagic(Not)
  else:
    let msg = fmt"== not supported by int and {other.pyType.name}"
    result = newTypeError(newPyStr msg)

implIntMagic repr:
  var s: string
  retIfExc self.toStringCheckThreshold s
  newPyAscii(s)


implIntMagic hash: self

# long_long
implIntMagic int:
  if self.ofExactPyIntObject:
    self
  else:
    newPyInt self

implIntMagic float:
  var ovf: PyOverflowErrorObject
  let ret = self.toFloat(ovf)
  if ovf.isNil:
    newPyFloat ret
  else:
    ovf


implIntMethod bit_length(): self.bit_length()
implIntMethod bit_count(): self.bit_count()
implIntMethod is_integer(): pyTrueObj

proc formatValueInt(res: var string; self: PyIntObject, format_spec: string, spec: StandardFormatSpecifier){.raises: [FormatPyObjectError].} =
  var str: PyStrObject
  var s: string
  #TODO:NIMPYLIB
  #TODO:format
  if spec.typ == 'c':
    # error to specify a sign
    if spec.sign != '\0':
        raisePyFormatExc newValueError(newPyAscii(
            "Sign not allowed with integer" &
              " format specifier 'c'"))
    # error to request alternate format
    if spec.alternateForm:
        raisePyFormatExc newValueError(newPyAscii(
            "Alternate form (#) not allowed with integer" &
              " format specifier 'c'"))

    # taken from unicodeobject.c formatchar()
    # Integer input truncated to a character
    var x: int
    let ovf = self.toInt x
    if ovf or 
      (x < 0 or x > 0x10ffff):
        raisePyFormatExc newOverflowError newPyAscii(
                        "%c arg not in range(0x110000)")
    str = newPyStr(cast[Rune](x))
    # inumeric_chars = 0;
    # n_digits = 1
    #[As a sort-of hack, we tell calc_number_widths that we only
        have "remainder" characters. calc_number_widths thinks
        these are characters that don't get formatted, only copied
        into the output string. We do this for 'c' formatting,
        because the characters are likely to be non-digits.]#
    # n_remainder = 1
    res.formatValue(str, format_spec)
  else:
    var base: uint8

    # We will dispatch formatValue via string type
    var sformat_spec = format_spec
    let L = sformat_spec.len
    if L > 0:
      sformat_spec.setLen(L - 1)

    #PY-DIFF: align is '<' by default for all types in Python
    # but in Nim, string defaults in '>' (and only strings, not other types)
    if spec.align == '\0':  # if align is to be defaulted
      # spec starts with `[[fill]align]`
      if spec.fill == ' ':
        sformat_spec = '>' & sformat_spec
      else:
        sformat_spec = spec.fill & '>' & sformat_spec[1..^1]

    echo sformat_spec
    case spec.typ
    of 'x', 'X': base = 16
    of 'b': base = 2
    of 'o': base = 8
    else:
      #'\0', 'n', 'd':
      let exc = self.toStringCheckThreshold(s)
      if not exc.isNil:
        raisePyFormatExc exc
      handleValueErrorAsPyFormatExc:
        res.formatValue(s, sformat_spec)
      return

    let exc = self.format_binary(base, spec.alternateForm, s)
    if not exc.isNil:
      raisePyFormatExc exc
    handleValueErrorAsPyFormatExc:
      res.formatValue(s, sformat_spec)

template impl(res, self, format_spec) =
    when format_spec is static:
      const spec = format_spec.parseStandardFormatSpecifier
    else:
      let spec = format_spec.parseStandardFormatSpecifier
    case spec.typ
    of {'f', 'F', 'e', 'E', 'g', 'G', '%'}:
      var ovf: PyOverflowErrorObject
      let ret = self.toFloat(ovf)
      if not ovf.isNil:
        raisePyFormatExc ovf
      let f = newPyFloat ret
      res.formatValue(f, format_spec)
    else:
      formatValueInt(res, self, format_spec, spec)

implFormatValue int, impl
genFormat int

implIntMagic New(tp: PyObject, *actualArgs):
  var x, obase: PyObject
  unpackOptArgs(actualArgs, "int", 0, 2, x, obase)
  long_new_impl(PyTypeObject tp, x, obase)



import ../stringobject/fstring
import ./floatobject/toval
import ./numobjects_comm
import ./intobject/magicNew
import ./intobject/ops
import ./intobject
import pkg/intobject/[decl, ops_strformat]
import ../[byteobjects, noneobject]
import ../../Python/getargs
import ../../Python/getargs/va_and_kw
import ../../Include/internal/pycore_global_strings

methodMacroTmpl(Int)

template check_binop_noSelfCast: untyped{.dirty.} = 
  if not selfNoCast.ofPyIntObject or not other.ofPyIntObject: return pyNotImplemented
template check_binop: untyped{.dirty.} = 
  check_binop_noSelfCast
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

implIntMagic divmod, [noSelfCast]: check_binop_do(divmod)

implIntMagic pow(selfNoCast, other: PyObject, modu = PyObject pyNone):
  check_binop_noSelfCast
  let self1 = PyIntObject selfNoCast
  if modu.isPyNone:
    pow(self1, PyIntObject(other))
  elif modu.ofPyIntObject:
    pow(self1, PyIntObject(other), PyIntObject(modu))
  else:
    return pyNotImplemented

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

template recatchValueError(body: untyped): untyped =
  try:
    body
  except ValueError as e:
    return newValueError newPyAscii e.msg

proc to_bytes*(self: PyIntObject; length: PyIntObject, byteorder = pyId "big", signed=pyFalseObj): PyObject =
  let length = length.toIntOrRetOF
  let endianness = recatchValueError parseByteOrder $byteorder.str
  newPyBytes self.to_bytes(length, endianness, signed=signed.b)

template asStr(byteorder: PyObject): string =
  let sbyteorder = byteorder.castTypeOrRetTE(PyStrObject)
  $sbyteorder.str

implIntMethod to_bytes(length=1, byteorder = PyObject pyId "big", signed=false):
  newPyBytes recatchValueError self.to_bytes(length, byteorder.asStr, signed)

implIntMethod from_bytes(bytes: PyObject, byteorder = PyObject pyId "big", signed=false), [classmethod]:
  let endianness = recatchValueError parseByteOrder byteorder.asStr
  let t = if bytes.ofPyBytesObject:
    PyBytesObject(bytes).items
  elif bytes.ofPyByteArrayObject:
    PyByteArrayObject(bytes).items
  else:
    return bufferNotImpl()
  newPyInt(t, endianness, signed)

template recatchValueErrorOrOvf(body: untyped): untyped =
  try: body
  except ValueError as e:
    raisePyFormatExc newValueError newPyAscii e.msg
  except IntObjectFormatOverflowError as e:
    raisePyFormatExc newOverflowError newPyAscii e.msg

template toIntObject(x: PyIntObject): IntObject = x.v

private_gen_formatValue_impl newPyString, newPyFloat, toIntObject, recatchValueErrorOrOvf

implFormatValue int, impl
genFormat int

implIntMagic New(tp: PyObject, *actualArgs):
  var x, obase: PyObject
  unpackOptArgs(actualArgs, "int", 0, 2, x, obase)
  long_new_impl(PyTypeObject tp, x, obase)


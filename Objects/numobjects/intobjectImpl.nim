
import std/strformat
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


implIntMagic New(tp: PyObject, *actualArgs):
  var x, obase: PyObject
  unpackOptArgs(actualArgs, "int", 0, 2, x, obase)
  long_new_impl(PyTypeObject tp, x, obase)


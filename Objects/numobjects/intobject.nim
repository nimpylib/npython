
import std/strformat
import std/strutils
import ./numobjects_comm
import ../../Utils/trans_imp
impExp intobject,
  decl, ops, idxHelpers, bit_length

methodMacroTmpl(Int)


template intBinaryTemplate(op, methodName: untyped, methodNameStr:string) = 
  if other.ofPyIntObject:
    #result = newPyInt(self.v.op PyIntObject(other).v)
    result = self.op PyIntObject(other)
  elif other.ofPyFloatObject:
    let newFloat = newPyFloat(self)
    result = newFloat.callMagic(methodName, other)
  else:
    let msg = methodnameStr & fmt" not supported by int and {other.pyType.name}"
    result = newTypeError(newPyAscii msg)

implIntMagic add:
  intBinaryTemplate(`+`, add, "+")


implIntMagic sub:
  intBinaryTemplate(`-`, sub, "-")


implIntMagic mul:
  intBinaryTemplate(`*`, mul, "*")


implIntMagic trueDiv:
  let casted = newPyFloat(self) ## XXX: TODO: ref long_true_divide
  casted.callMagic(trueDiv, other)


implIntMagic floorDiv:
 if other.ofPyIntObject:
   self // PyIntObject(other)
 elif other.ofPyFloatObject:
   let newFloat = newPyFloat(self)
   return newFloat.callMagic(floorDiv, other)
 else:
   return newTypeError(newPyString fmt"floor divide not supported by int and {other.pyType.name}")

implIntMagic Mod:
  intBinaryTemplate(`%`, pow, "%")

implIntMagic pow:
  intBinaryTemplate(pow, pow, "**")


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

implIntMagic str:
  newPyAscii($self)


implIntMagic repr:
  newPyAscii($self)


implIntMagic hash:
  self

implIntMagic New:
  checkArgNum(2)
  let arg = args[1]
  case arg.pyType.kind
  of PyTypeToken.Int:
    return arg
  of PyTypeToken.Float:
    let iStr = $cast[PyFloatObject](arg).v
    return newPyInt(iStr.split(".")[0])
  of PyTypeToken.Str:
    let str = cast[PyStrObject](arg).str
    try:
      return str.doBothKindOk newPyInt
    except ValueError:
      let msg = fmt"invalid literal for int() with base 10: '{str}'"
      return newValueError(newPyStr msg)
  of PyTypeToken.Bool:
    if cast[PyBoolObject](arg).b:
      return pyIntOne
    else:
      return pyIntZero
  else:
    return newTypeError(newPyStr fmt"Int argument can't be '{arg.pyType.name}'")

implIntMethod bit_length(): self.bit_length()
implIntMethod bit_count(): self.bit_count()
implIntMethod is_integer(): pyTrueObj

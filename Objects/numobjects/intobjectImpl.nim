
import std/strformat
import ./numobjects_comm
import ./intobject/magicNew
import ./intobject
import ../../Python/getargs

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
  intBinaryTemplate(`%`, Mod, "%")

implIntMagic pow:
  intBinaryTemplate(pow, pow, "**")

proc binop_type_error(v, w: PyObject, op_name: string): PyTypeErrorObject =
  newTypeError newPyStr fmt"unsupported operand type(s) for {op_name:.100s}: '{v.typeName:.100s}' and '{w.typeName:.100s}'"
template binary_op1(op; magicop; opname) =
  #TODO:bop  for other types
  if not other.ofPyIntObject:
    return binop_type_error(self, other, opname)
  result = op(self, PyIntObject(other))

implIntMagic abs: abs self
implIntMagic And: binary_op1(`and`, And, "&")
implIntMagic Or: binary_op1(`or`, Or, "|")
implIntMagic Xor: binary_op1(`xor`, Xor, "^")
implIntMagic lshift: binary_op1(`shl`, lshift, "<<")
implIntMagic rshift: binary_op1(`shr`, rshift, ">>")
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

implIntMagic str:
  newPyAscii($self)


implIntMagic repr:
  newPyAscii($self)


implIntMagic hash:
  self


implIntMethod bit_length(): self.bit_length()
implIntMethod bit_count(): self.bit_count()
implIntMethod is_integer(): pyTrueObj


implIntMagic New(tp: PyObject, *actualArgs):
  var x, obase: PyObject
  unpackOptArgs(actualArgs, "int", 0, 2, x, obase)
  long_new_impl(PyTypeObject tp, x, obase)


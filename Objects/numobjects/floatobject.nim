

import std/strformat
import std/macros
import std/parseutils
import std/math
import std/hashes
#TODO:magic int,float

import ./numobjects_comm
export floatobject_decl

methodMacroTmpl(Float)

template asDouble*(op: PyFloatObject): float = op.v
template asDouble*(op: PyFloatObject; v: var float): PyBaseErrorObject =
  v = op.asDouble
  PyBaseErrorObject nil
proc PyFloat_AsDouble*(op: PyObject; v: var float): PyBaseErrorObject =
  if op.ofPyFloatObject:
    return op.PyFloatObject.asDouble v
  var fun = op.pyType.magicMethods.float
  if fun.isNil:
    var res: PyIntObject
    let exc = PyNumber_Index(op, res)
    if exc.isNil:
      v = res.toFloat
      return
  else:
    let res = fun(op)
    errorIfNot Float, "float", res, (op.typeName & ".__float__")
    return res.PyFloatObject.asDouble v

proc PyFloat_AsFloat*(op: PyObject; v: var float32): PyBaseErrorObject =
  ## EXT.
  var df: float
  result = PyFloat_AsDouble(op, df)
  if result.isNil:
    v = float32 df

template castOtherTypeTmpl(methodName) = 
  var casted {. inject .} : PyFloatObject
  if other.ofPyFloatObject:
    casted = PyFloatObject(other)
  elif other.ofPyIntObject:
    casted = newPyFloat(PyIntObject(other))
  else:
    let msg = methodName & fmt" not supported by float and {other.typeName}"
    return newTypeError(newPyStr msg)

macro castOther(code:untyped):untyped = 
  let fullName = code.name.strVal
  let d = fullName.skipUntil('P') # add'P'yFloatObj, luckily there's no 'P' in magics
  let methodName = fullName[0..<d]
  code.body = newStmtList(
    getAst(castOtherTypeTmpl(methodName)),
    code.body
  )
  code

template genBin(magic, op; ret: untyped=newPyFloat){.dirty.} =
  implFloatMagic magic, [castOther]:
    ret op(self.v, casted.v)

genBin add, `+`
genBin sub, `-`
genBin mul, `*`
genBin trueDiv, `/`

proc floorDivNonZero(a, b: PyFloatObject): PyFloatObject =
  newPyFloat(floor(a.v / b.v))

proc floorModNonZero(a, b: PyFloatObject): PyFloatObject =
  newPyFloat(floorMod(a.v, b.v))

template genDivOrMod(dm, mag){.dirty.} =
  proc `floor dm`(a, b: PyFloatObject): PyObject =
    if b.v == 0:
      retZeroDiv
    `floor dm NonZero` a, b

  implFloatMagic mag, [castOther]:
    `floor dm` self, casted

genDivOrMod Div, floorDiv
genDivOrMod Mod, Mod

proc divmodNonZero*(a, b: PyFloatObject): tuple[d, m: PyFloatObject] =
  ## export for builtins.divmod
  result.d = a.floorDivNonZero b
  result.m = a.floorModNonZero b

proc divmod*(a, b: PyFloatObject): tuple[d, m: PyFloatObject] =
  if b.v == 0.0:
    raise newException(ValueError, "division by zero")
  divmodNonZero(a, b)


implFloatMagic pow, [castOther]:
  newPyFloat(self.v.pow(casted.v))


implFloatMagic positive: self

implFloatMagic negative: newPyFloat(-self.v)


implFloatMagic bool: newPyBool self.v != 0

template genBBin(magic, op){.dirty.} = genBin(magic, op, newPyBool)

genBBin lt, `<`
genBBin eq, `==`
genBBin gt, `>`


implFloatMagic str:
  newPyAscii($self)


implFloatMagic repr:
  newPyAscii($self)

implFloatMagic hash:
  newPyInt(hash(self.v))


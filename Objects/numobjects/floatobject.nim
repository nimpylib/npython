

import std/strformat
import std/macros
import std/parseutils
import std/math
import std/hashes
import ../../Utils/trans_imp
impExp floatobject,
  decl, toval, fromx

import ./numobjects_comm
export floatobject_decl

methodMacroTmpl(Float)


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


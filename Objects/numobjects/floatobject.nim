

import std/strformat
import std/macros
import std/parseutils
import std/math
import std/hashes
import ../../Utils/trans_imp
impExp floatobject,
  decl, toval, fromx

from ./intobject/ops import newPyInt
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

proc abs*(self: PyFloatObject): PyFloatObject = newPyFloat(abs(self.v))
implFloatMagic abs: abs self
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


# long_long
implFloatMagic int: newPyInt self.v

implFloatMagic float:
  if self.ofExactPyFloatObject:
    self
  else:
    newPyFloat self

proc float_subtype_new(typ: PyTypeObject, x: PyObject): PyObject{.pyCFuncPragma.}
proc float_new_impl(typ: PyTypeObject, x: PyObject = nil): PyObject{.pyCFuncPragma.} =
  let noX = x.isNil
  if not typ.isType pyFloatObjectType:
    return float_subtype_new(typ, (if noX: pyIntZero else: x))
  if noX:
    return newPyFloat(0.0)
  #[If it's a string, but not a string subclass, use
       PyFloat_FromString.]#
  if x.ofExactPyStrObject:
    return PyFloat_FromString(PyStrObject x)
  return PyNumber_Float(x)

proc float_subtype_new(typ: PyTypeObject, x: PyObject): PyObject =
  #[ Wimpy, slow approach to tp_new calls for subtypes of float:
    first create a regular float from whatever arguments we got,
    then allocate a subtype instance and initialize its ob_fval
    from the regular float.  The regular float is then thrown away.
  ]#

  when declared(PyType_IsSubtype):
    assert PyType_IsSubtype(typ, pyFloatObjectType)
  let tmp = float_new_impl(pyFloatObjectType, x)
  retIfExc tmp
  assert tmp.ofPyFloatObject
  result = typ.tp_alloc(typ, 0)
  retIfExc result
  ((PyFloatObject)result).v = ((PyFloatObject)tmp).v


implFloatMagic New:
  checkArgNum 1, 2
  let typ = PyTypeObject args[0]
  let noX = args.len == 1
  var x: PyObject
  if not noX: x = args[1]
  float_new_impl(typ, x)


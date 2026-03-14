
import std/strformat

import ./numobjects_comm
import ./complexobject_decl
export complexobject_decl

import ./complexobject/[utils, pow]
export pow

from std/complex import Complex
import pkg/pycomplex

from ./floatobject/toval import PyFloat_AsDouble
from ./floatobject/fromx import PyNumber_Float
import ../noneobject
import ../typeobject/apis/attrs
import ../../Include/internal/pycore_global_strings
import ../../Python/getargs
import ../../Python/warnings
import ../../Python/call

proc try_complex_special_method(op: PyObject): PyObject {.raises: [].}

proc newSubPyComplexFromDoubles(tp: PyTypeObject, cval: PyComplex): PyObject =
  ## complex_subtype_from_c_complex
  result = tp.tp_alloc(tp, 0)
  retIfExc result
  result.PyComplexObject.v = cval
  
proc newSubPyComplexFromDoubles(tp: PyTypeObject, re, im: float): PyObject =
  ## complex_subtype_from_doubles
  newSubPyComplexFromDoubles tp, complex(re, im)

proc newPyComplexImpl(real, imag: PyObject, tp: PyTypeObject): PyObject =
  ## imag must not be nil
  assert imag.isNil.not
  var re, im: float
  var
    cr_is_complex = false
    ci_is_complex = false
    cr, ci: PyComplex
  if real.ofPyComplexObject:
    if real.getMagic(float).isNil and real.getMagic(int).isNil:
      retIfExc warnEx(pyDeprecationWarningObjectType,
        "complex() first argument 'real' must be a real number, not " & real.typeName)
    cr_is_complex = true
    cr = real.PyComplexObject.v
  else:
    retIfExc PyFloat_AsDouble(real, re)
  if imag.ofPyComplexObject:
    retIfExc warnEx(pyDeprecationWarningObjectType,
      "complex() second argument 'imag' must be a real number, not " & imag.typeName)
    ci_is_complex = true
    ci = imag.PyComplexObject.v
  else:
    retIfExc PyFloat_AsDouble(imag, im)
  if ci_is_complex:
    re -= ci.imag
  if cr_is_complex:
    re += cr.imag
  newSubPyComplexFromDoubles tp, re, im

proc newPyComplex*(real, imag: PyObject): PyObject =
  newPyComplexImpl(real, imag, pyComplexObjectType)

proc newPyComplexImpl(x: openArray[char], tp: PyTypeObject): PyObject{.raises: [].} =
  newSubPyComplexFromDoubles tp, try: complex x
  except ValueError as e:
    return newValueError newPyStr e.msg

proc newPyComplexImpl(obj: PyObject, tp: PyTypeObject): PyObject {.raises: [].} =
  if obj.ofPyStrObject:
    newPyComplexImpl $obj.PyStrObject.str, tp
  elif obj.getMagic(float).isNil and obj.getMagic(int).isNil:
    if obj.ofPyComplexObject:
      retIfExc warnEx(pyDeprecationWarningObjectType,
        "complex() argument 'real' must be a real number, not " & obj.typeName)
    return newTypeError newPyStr "complex() argument 'real' must be a real number, not " & obj.typeName
  elif obj.ofPyComplexObject:
    newPyComplex obj.PyComplexObject.v
  else:
    let special = try_complex_special_method(obj)
    if not special.isNil:
      retIfExc special
      var f: PyFloatObject
      retIfExc PyNumber_Float(special, f)
      return newPyComplex f
    var f: float
    retIfExc PyFloat_AsDouble(obj, f)
    newPyComplex f

proc newPyComplex*(obj: PyObject): PyObject {.raises: [].} = newPyComplexImpl(obj, pyComplexObjectType)


methodMacroTmpl(Complex)
template genPro(n){.dirty.} =
  genProperty Complex, astToStr(n), n, newPyFloat self.n

genPro real
genPro imag

implComplexMethod "__complex__"(): self
proc conjugate*(self: PyComplexObject): PyComplexObject = newPyComplex self.v.conjugate()
implComplexMethod conjugate(): self.conjugate()

implComplexMethod "__format__"(arg: PyStrObject):
  var res: string
  try:
    res.formatValue self.v, $arg.str
  except ValueError as e:
    return newValueError newPyAscii e.msg
  newPyAscii res

implComplexMagic repr: newPyAscii pycomplex.repr(self.v)



template genBop(op){.dirty.} =
  proc op*(self, other: PyComplexObject): `PyComplexObject` =
    `newPyComplex` op(self.v, other.v)

template genBMagic(magic, op){.dirty.} =
  genBop op
  implComplexMagic magic, [noSelfCast]:
    COMPLEX_BINOPimpl astToStr(op), op


genBMagic add, `+`
genBMagic sub, `-`
genBMagic mul, `*`
genBMagic trueDiv, `/`

#genBMagicAux pow, `**`, PyObject, newPyComplexNoMod
genBop pow
implComplexMagic pow:
  pow3rdArgMustBeNone
  complex_pow(self, other)

proc `==`*(self, other: PyComplexObject): bool = pycomplex.`==`(self.v, other.v)
implComplexMagic eq:
  if other.ofPyIntObject:
    if self.imag == 0:
      return newPyBool newPyFloat(self.real) == newPyFloat PyIntObject(other).toFloat
    else:
      return pyFalseObj
  elif other.ofPyFloatObject:
    return newPyBool self.real == other.PyFloatObject.v and self.imag == 0
  elif other.ofPyComplexObject:
    return newPyBool self == PyComplexObject(other)
  else:
    return pyNotImplemented


template `+`[T](x: Complex[T]): Complex[T] = x
func toBool(x: PyComplex): bool = x.real != 0 or x.imag != 0

template genUMagic(magic, op, T){.dirty.} =
  proc op*(self: PyComplexObject): `Py T Object` =
    `newPy T` op(self.v)
  implComplexMagic magic: op(self)

template genUMagic(magic, op) = genUMagic(magic, op, Complex)

proc abs*(self: PyComplexObject): PyFloatObject = newPyFloat pycomplex.abs(self.v)

genUMagic negative, `-`
genUMagic positive, `+`
genUMagic bool, toBool, Bool

proc try_complex_special_method(op: PyObject): PyObject {.raises: [].} =
  let f = PyObject_LookupSpecial(op, pyDUId complex)
  if f.isNil or f.isThrownException:
    return f

  let res = f.call()
  retIfExc res
  if not res.ofPyComplexObject:
    return newTypeError newPyStr fmt"{op.typeName}.__complex__() must return a complex, not {res.typeName}"

  #[ Issue #29894: warn if 'res' not of exact type complex. ]#
  retIfExc warnEx(
    pyDeprecationWarningObjectType,
    fmt"{op.typeName}.__complex__() must return a complex, not {res.typeName}. " &
      "The ability to return an instance of a strict subclass of complex " &
      "is deprecated, and may be removed in a future version of Python."
  )
  res


implComplexMagic New(tp0: PyObject, re = PyObject newPyFloat 0, im = PyObject nil):
  let tp = tp0.PyTypeObject
  if im.isNil:
    if re.ofExactPyComplexObject and tp.isType pyComplexObjectType:
      return re
    
    newPyComplex re
  else:
    newPyComplexImpl(re, im, tp)



import pkg/intobject
import pkg/pymath
import pkg/handy_sugars/trans_imp

import ../Objects/[
  pyobject,
  bltcommon,
  exceptions,
  boolobject,
  moduleobjectImpl,
  stringobject,
  numobjects,
  tupleobjectImpl,
]
import ../Python/getargs/[tovals,
  paramsMeta,
  dispatch,
]
import ./math/utils
impExpCwd math, [
  init,
  vec_op, reduce, prod, sumprod,
]
methodMacroTmpl(mathModule)

template gen_const(nam) {.dirty.} =
  genProperty MathModule, astToStr(nam), nam: newPyFloat(pymath.nam)

gen_const pi
gen_const e
gen_const tau
gen_const inf
gen_const nan

template gen_func1(nam) {.dirty.} =
  implMathModuleMethod nam(x: float): newPyFloat(nam x)
template gen_fun2i(nam) {.dirty.} =
  implMathModuleMethod nam(x: float, i: int): newPyFloat(pymath.nam(x, i))

template orRetValErr(pyexp): PyObject =
    try: pyexp
    except ValueError as e: return newValueError newPyAscii e.msg
template gen_funci(nam) {.dirty.} =
  implMathModuleMethod nam(x: float):
    newPyFloat(float pymath.nam x).orRetValErr
template gen_func2(nam) {.dirty.} =
  implMathModuleMethod nam(x: float, y: float): newPyFloat(pymath.nam(x, y))
template gen_fufma(nam) {.dirty.} =
  implMathModuleMethod nam(x: float, y: float, z: float):
    var e: ref Exception
    let res = nam(x, y, z, e)
    if e.isNil.not:
      if e.name == "ValueError": return newValueError newPyAscii e.msg
      else: return newOverflowError newPyAscii e.msg
    newPyFloat(res)

template toPyObject(i: int): PyObject = newPyInt i
template toPyObject(i: float): PyObject = newPyFloat i

template gen_funct(nam) {.dirty.} =
  implMathModuleMethod nam(x: float):
    let t = pymath.nam(x)
    newPyTuple([t[0].toPyObject, t[1].toPyObject])

template gen_funcb(nam) {.dirty.} =
  implMathModuleMethod nam(x: float): newPyBool(pymath.nam(x))

proc toval(obj: PyObject, i: var IntObject): PyBaseErrorObject =
  var iobj: PyIntObject
  retIfExc PyNumber_Index(obj, iobj)
  i = iobj.v
template gen_funii(nam) {.dirty.} =
  implMathModuleMethod nam(x: IntObject): newPyInt(nam(x)).orRetValOrOvfErr

template gen_fuiii(nam) {.dirty.} =
  implMathModuleMethod nam(x: IntObject, y: IntObject): newPyInt(nam(x, y)).orRetValOrOvfErr

proc isclose(
        x: float, y: float,
        rel_tol{.startKwOnly.}: float = 1e-09, abs_tol: float = 0.0
    ): bool{.clinicGenStaticMethodAndRaises(MathModule, [ValueError]).} =
  pymath.isclose(x, y, rel_tol, abs_tol)

gen_func1 acos
gen_func1 acosh
gen_func1 asin
gen_func1 asinh
gen_func1 atan
gen_func2 atan2
gen_func1 atanh
gen_func1 cbrt
gen_funci ceil
gen_fuiii comb
gen_func2 copysign
gen_func1 cos
gen_func1 cosh
gen_func1 degrees
#en_funp2 dist    #done reduce
gen_func1 erf
gen_func1 erfc
gen_func1 exp
gen_func1 exp2
gen_func1 expm1
gen_func1 fabs
gen_funii factorial
gen_funci floor
gen_func2 fmod
gen_fufma fma
gen_funct frexp
#en_func1 fsum    #done vec_op
gen_func1 gamma
#en_funiN gcd
#en_funfN hypot   #done reduce
#en_fubfx isclose #done above
gen_funcb isfinite
gen_funcb isinf
gen_funcb isnan
gen_funii isqrt
#en_funiN lcm
gen_fun2i ldexp
gen_func1 lgamma
gen_func2 log
gen_func1 log10
gen_func1 log1p
gen_func1 log2
gen_funct modf
gen_func2 nextafter
gen_fuiii perm
gen_func2 pow
#en_funix prod
gen_func1 radians
gen_func2 remainder
gen_func1 sin
gen_func1 sinh
gen_func1 sqrt
#en_funcx sumprod
gen_func1 tan
gen_func1 tanh
gen_funci trunc
gen_func1 ulp


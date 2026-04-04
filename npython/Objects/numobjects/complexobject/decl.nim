

import ../../pyobject
import ../floatobject/decl
import std/complex
import pkg/pycomplex
declarePyType Complex(tpToken):
  v: PyComplex

using self: PyComplexObject

method `$`*(self): string{.raises: [].} = pycomplex.`$` self.v

proc newPyComplex*(re: SomeFloat = 0, im: SomeFloat = 0): PyComplexObject =
  result = newPyComplexSimple()
  result.v = complex(re, im)

proc newPyComplex*(re: PyFloatObject, im: PyFloatObject = newPyFloat 0): PyComplexObject =
  newPyComplex(re.v, im.v)

proc newPyComplex*(x: PyComplex): PyComplexObject =
  result = newPyComplexSimple()
  result.v = x

proc newPyComplex*(x: PyComplexObject): PyComplexObject = newPyComplex x.v
proc newPyComplex*(x: openArray[char]): PyComplexObject = newPyComplex complex x

template real*(self: PyComplexObject): float = self.v.real
template imag*(self: PyComplexObject): float = self.v.imag

func toNimComplex*(self: PyComplexObject): Complex[float] = self.v.toNimComplex

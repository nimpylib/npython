## Used by ./frexp.nim

import std/fenv
const
  DBL_MAX_EXP* = float.maxExponent  ## inner, for PyLong_AsDouble
  DBL_MAX*     = float.maximumPositiveValue
  DBL_MAX_10_EXP* = float.max10Exponent
  DBL_MIN*     = float.minimumPositiveValue
  DBL_MIN_EXP* = float.minExponent
  DBL_MIN_10_EXP* = float.min10Exponent
  DBL_DIG*     = float.digits
  DBL_MANT_DIG* = float.mantissaDigits
  DBL_EPSILON* = float.epsilon
  FLT_RADIX*   = fpRadix()
  #FLT_ROUNDS*  = 
const weirdTarget = defined(js) or defined(nimscript)
when not weirdTarget:
  let fiRound = fegetround().int
  template FLT_ROUNDS*: int =
    ## not available when nimscript
    bind fiRound
    fiRound
else:
  template FLT_ROUNDS*: int =
    #{.error: "not available for nimscript/JavaScript/compile-time".}
    -1

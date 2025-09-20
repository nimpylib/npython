
import ./decl


proc newPyIntOfLen*(L: int): PyIntObject =
  ## `long_alloc`
  ## 
  ## result sign is `Positive` if l != 0; `Zero` otherwise
  result = newPyIntSimple()
  result.digits.setLen(L)
  if L != 0:
    result.sign = Positive

when declared(setLenUninit):
  template setLenUninit*(intObj: PyIntObject, L: int) =
    intObj.digits.setLenUninit(L)
else:
  template setLenUninit*(intObj: PyIntObject, L: int) =
    intObj.digits.setLen(L)

proc newPyIntOfLenUninit*(L: int): PyIntObject =
  result = newPyIntSimple()
  result.setLenUninit(L)
  if L != 0:
    result.sign = Positive

proc setSignAndDigitCount*(intObj: PyIntObject, sign: IntSign, digitCount: int) =
  ## `_PyLong_SetSignAndDigitCount`
  intObj.sign = sign
  intObj.digits.setLen(digitCount)

proc copy*(intObj: PyIntObject): PyIntObject =
  ## XXX: copy only digits (sign uninit!)
  let newInt = newPyIntSimple()
  newInt.digits = intObj.digits
  newInt
proc normalize*(a: PyIntObject) =
  for i in 0..<a.digits.len:
    if a.digits[^1] == 0:
      discard a.digits.pop()
    else:
      break

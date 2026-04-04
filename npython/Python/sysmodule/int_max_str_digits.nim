
import ../../Objects/[exceptions, stringobject,]
import ../../Include/internal/pycore_int


proc PySys_SetIntMaxStrDigits*(maxdigits: int): PyBaseErrorObject =
  if maxdigits != 0 and maxdigits < PY_INT_MAX_STR_DIGITS_THRESHOLD:
    return newValueError newPyAscii(
      "maxdigits must be >= " & $PY_INT_MAX_STR_DIGITS_THRESHOLD & " or 0 for unlimited"
    )
  PyInterpreterState_GET_long_state().max_str_digits = maxdigits

proc PySys_GetIntMaxStrDigits*: int = PyInterpreterState_GET_long_state().max_str_digits


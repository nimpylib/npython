## `pycore_long.h`

const
  PY_INT_MAX_STR_DIGITS_THRESHOLD*{.intdefine: "PY_LONG_MAX_STR_DIGITS_THRESHOLD".} = 640 ## `_PY_LONG_MAX_STR_DIGITS_THRESHOLD`
  PY_INT_DEFAULT_MAX_STR_DIGITS*{.intdefine: "PY_LONG_DEFAULT_MAX_STR_DIGITS".} = 4300  ## `_PY_LONG_DEFAULT_MAX_STR_DIGITS`\
  ## set as default of `config->int_max_str_digits`
static:assert PY_INT_DEFAULT_MAX_STR_DIGITS >= PY_INT_MAX_STR_DIGITS_THRESHOLD

type Py_long_state = object
  max_str_digits*: int

var state{.threadVar.}: Py_long_state

proc PyInterpreterState_GET_long_state*(): var Py_long_state{.inline.} =
  ## `_PyInterpreterState_GET->long_state`
  state

template pre = result.add "Exceeds the limit (" & $cfg_max & " digits) for integer string conversion"
template suf = result.add "; use sys.set_int_max_str_digits() to increase the limit"
proc MAX_STR_DIGITS_errMsg_to_int*(cfg_max, d: int): string =
  pre
  result.add ": value has " & $d & " digits"
  suf

proc MAX_STR_DIGITS_errMsg_to_str*(cfg_max: int): string = pre; suf

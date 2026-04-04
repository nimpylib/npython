
when declared(WITH_DOC_STRINGS):
  template PyDoc_STR(str): untyped = cstring str
else:
  template PyDoc_STR(str): untyped = cstring ""

template PyDoc_STRVAR*(name; str) =
  bind PyDoc_STR
  const name = PyDoc_STR(str)

template Py_SIZE_ROUND_UP*(n, a): uint =
  ## `_Py_SIZE_ROUND_UP`
  ## Round up size "n" to be a multiple of "a".
  (uint(n) + uint(a - 1)) and
        not uint(a - 1)


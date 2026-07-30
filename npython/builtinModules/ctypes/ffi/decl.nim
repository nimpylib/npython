
import ../dll/decl
import ../../private/[utils]
import ./ffi/libffi

impObjects [
  pyobject,
  stringobject,
  dictobject,
]


declarePyType CFunc(dict):
  dll: PyCDLLObject
  name: PyStrObject
  handle: pointer
  argtypes{.member, nil2none.}: PyObject  # tuple/list
  restype{.member, nil2none.}: PyObject
  callback: PyObject
  closure: ptr Closure
  cif: TCif
  ffiTypes: seq[ptr Type]


import pkg/libffi

import pkg/py_locale_utf8_encoding/wchar_t as wcharLib
when defined(nimPreviewSlimSystem): import std/assertions
import ../private/[utils]
import ./[decl, cdata, ]
import ./ffi/ffi
impObjects stringobject/wchars/torunes
impObjects [
  pyobject,
  bltcommon,
  exceptions,
  stringobject,
  byteobjects,
  numobjects/intobject,
  pyobject_apis/attrs,
]
imp Python, sysmodule
imp Python, getargs/tovals
imp Python, getargs/nokw
import ./common

methodMacroTmpl(CtypesModule)

proc ctypeSizeUnsafe*(typ: PyTypeObject): int =
  ## unsafe as assuming `typ` is a ctypes type (a.k.a.
  ##   in CPython, can be used in `ctypes.sizeof`)
  let size = PyObject_GetAttr(typ, ctypeSizeAttrName)
  assert size.ofPyIntObject
  PyIntObject(size).toSomeSignedIntUnsafe[:int]

proc addressof*(obj: PyObject): PyObject =
  ## Return the address of the given object as a Python integer.
  ##  `obj` must be an instance of a ctypes type.
  if not obj.ofPyCDataObject:
    return newTypeError newPyStr("addressof() argument must be _ctypes._CData, not " & obj.typeName)
  newPyIntFromPtr PyCDataObject(obj).addressof

implCTypesModuleMethod addressof(obj):
  retIfExc audit("ctypes.addressof", obj)
  addressof obj

implCTypesModuleMethod sizeof(x):
  let typ =
    if x.ofPyTypeObject: PyTypeObject(x)
    else: x.pyType
  result = PyObject_GetAttr(typ, ctypeSizeAttrName)
  if result.isExceptionOf Attribute:
    return newTypeError newPyAscii"this type has no size"


implCTypesModuleMethod pointer(obj: PyCDataObject):
  newPyPointerTo(obj)

#NOTE: like CPython, SIGSEGV if p == 0 (NULL)

proc string_at*(p: pointer|(ptr char), size = -1): PyBytesObject =
  if size < 0:
    newPyBytesNotNil cast[cstring](p)
  else:
    newPyBytes(cast[cstring](p).toOpenArray(0, size-1))
implCTypesModuleMethod string_at(p: int, size = -1):
  retIfExc audit("ctypes.string_at", p, size)
  string_at(cast[pointer](p), size)

proc wstring_at*(p: pointer|(ptr wchar_t), size = -1): PyObject =
  if size < 0:
    newPyStr cast[ptr wchar_t](p)
  else:
    newPyStr cast[ptr UncheckedArray[wchar_t]](p).toOpenArray(0, size-1)
implCTypesModuleMethod wstring_at(p: int, size = -1):
  retIfExc audit("ctypes.wstring_at", p, size)
  wstring_at(cast[pointer](p), size)

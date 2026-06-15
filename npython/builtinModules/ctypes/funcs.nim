
when defined(nimPreviewSlimSystem): import std/assertions
import ../private/[utils]
import ./[decl,]
impObjects [
  pyobject,
  bltcommon,
  exceptions,
  stringobject,
  numobjects/intobject,
  pyobject_apis/attrs,
]
import ./common

methodMacroTmpl(CtypesModule)

proc ctypeSizeUnsafe*(typ: PyTypeObject): int =
  ## unsafe as assuming `typ` is a ctypes type (a.k.a.
  ##   in CPython, can be used in `ctypes.sizeof`)
  let size = PyObject_GetAttr(typ, ctypeSizeAttrName)
  assert size.ofPyIntObject
  PyIntObject(size).toSomeSignedIntUnsafe[:int]

implCTypesModuleMethod sizeof(x):
  let typ = x.pyType
  result = PyObject_GetAttr(typ, ctypeSizeAttrName)
  if result.isExceptionOf Attribute:
    return newTypeError newPyAscii"this type has no size"


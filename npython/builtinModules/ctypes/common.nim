import ../private/[utils]

impObjects [
  pyobject,
  stringobject,
  exceptions,
]
imp Include, internal/pycore_global_strings

template ctypeSizeAttrName*: PyStrObject =
  bind pyId
  pyId "_npy_ctype_size_"

template attrName*(obj: PyObject): PyStrObject =
  if not obj.ofPyStrObject:
    return newTypeError newPyAscii"attribute name must be string"
  PyStrObject obj

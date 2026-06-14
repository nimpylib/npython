import ../private/[utils]

impObjects [
  pyobject,
  stringobject,
  exceptions,
]


template attrName*(obj: PyObject): PyStrObject =
  if not obj.ofPyStrObject:
    return newTypeError newPyAscii"attribute name must be string"
  PyStrObject obj


include ./comm
impObjects [
  stringobject,
  byteobjects,
]

import ./[decl, fspath]
export decl

{.push raises: [].}
proc toPy*(x: PyPathStr, res: var PyObject): PyBaseErrorObject =
  res = newPyStr string(x)

proc toval*(x: PyObject, res: var PyPathStr): PyBaseErrorObject =
  var obj: PyObject
  retIfExc fspath(x, obj)
  if obj.ofPyStrObject:
    res = PyPathStr PyStrObject(obj).asUTF8
  elif obj.ofPyBytesObject:
    res = PyPathStr PyBytesObject(obj).asString
  else:
    return newTypeError newPyAscii("path should be string, bytes, or os.PathLike, not " & obj.typeName)

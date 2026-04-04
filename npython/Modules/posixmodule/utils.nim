
import std/strformat
import ../../Objects/[
  pyobjectBase,
  exceptions,
  stringobject,
  byteobjects,
  noneobject,
]
import ../../Objects/typeobject/apis/attrs
import ../../Include/internal/pycore_global_strings
import ../../Python/call


proc PyOS_FSPath*(path: PyObject): PyObject =
  ##[
    Return the file system path representation of the object.

    If the object is str or bytes, then allow it to pass through with
    an incremented refcount. If the object defines __fspath__(), then
    return the result of that method. All other types raise a TypeError.
  ]##
  #[ For error message reasons, this function is manually inlined in
      path_converter(). ]#

  if path.ofPyStrObject or path.ofPyBytesObject:
    return path

  var fun = PyObject_LookupSpecial(path, pyDUId(fspath))
  if fun.isNil or fun.isPyNone:
    return newTypeError newPyStr(
      fmt"expected str, bytes or os.PathLike object, not {path.typeName:.200s}")

  let path_repr = call(fun)
  if path_repr.isThrownException:
    return path_repr

  if not (path_repr.ofPyStrObject or path_repr.ofPyBytesObject):
    return newTypeError newPyStr(
      fmt"expected {path.typeName:.200s}.__fspath__() to return str or bytes, "&
        fmt"not {path.typeName:.200s}")

  return path_repr

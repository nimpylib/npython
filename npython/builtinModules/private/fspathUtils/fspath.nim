
include ./comm
import std/strformat
impObjects [
  stringobject,
  byteobjects,
  noneobject,
]

from pkg/pystrbytes_decl/strimpl import PyStr, str
from pkg/pystrbytes_decl/bytesimpl import PyBytes, bytes
imp Python, call
impObjects typeobject/apis/attrs
imp Utils, nexportc
imp Include, internal/pycore_global_strings

from pkg/pyio_abc import PathLike

func isStrOrBytes(path: PyObject): bool =
  path.ofPyStrObject or path.ofPyBytesObject

proc fspath*(path: PyObject; path_repr: var PyObject): PyBaseErrorObject {.raises: [].} =
  ##[
    Return the file system path representation of the object.

    If the object is str or bytes, then allow it to pass through with
    an incremented refcount. If the object defines __fspath__(), then
    return the result of that method. All other types raise a TypeError.
  ]##
  #[ For error message reasons, this function is manually inlined in
      path_converter(). ]#

  if path.isStrOrBytes:
    path_repr = path
    return

  var fun = PyObject_LookupSpecial(path, pyDUId(fspath))
  if fun.isNil or fun.isPyNone:
    return newTypeError newPyStr(
      fmt"expected str, bytes or os.PathLike object, not {path.typeName:.200s}")

  let tpath_repr = call(fun)
  retIfExc tpath_repr

  if not tpath_repr.isStrOrBytes:
    return newTypeError newPyStr(
      fmt"expected {path.typeName:.200s}.__fspath__() to return str or bytes, "&
        fmt"not {path.typeName:.200s}")

  path_repr = tpath_repr

proc fspath*(path: PyObject): PyObject{.npyexportc: "PyOS_FSPath".} =
  retIfExc fspath(path, result)

proc toval*[T](x: PyObject, res: var PathLike[T]): PyBaseErrorObject {.raises: [].} =
  var val: string
  var obj: PyObject
  retIfExc fspath(x, obj)
  if obj.ofPyStrObject and T is PyStr:
    val = PyStrObject(obj).asUTF8
  elif obj.ofPyBytesObject and T is PyBytes:
    val = PyBytesObject(obj).asString
  else:
    return newTypeError newPyAscii("path should be string, bytes, or os.PathLike, not " & obj.typeName)
  res = val



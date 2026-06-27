
when defined(nimPreviewSlimSystem):
  import std/assertions

include ./comm
impObjects [
  stringobject,
  byteobjects,
  tupleobjectImpl,
]
import pkg/pystrbytes_decl

import ./[decl, fspath, consts]
export decl

type PathLikeParseState = enum
  psNone, psStr, psBytes

var state{.threadVar.}: PathLikeParseState

proc restorePathLikeParseState* = state = psNone
{.push raises: [].}
when PyPathStr is_not PyStr:
 proc toPy*(x: PyPathStr, res: var PyObject): PyBaseErrorObject =
  assert state != psNone
  if state == psStr:
    res = newPyStr string(x)
  else:
    res = newPyBytes string(x)
else:
  imp Python, getargs/topys
  export toPy
proc toval*(x: PyObject, res: var PyPathStr): PyBaseErrorObject =
  var obj: PyObject
  retIfExc fspath(x, obj)
  if obj.ofPyStrObject:
    if state == psBytes:
      return cannotMixPathLikeError()
    res = PyPathStr PyStrObject(obj).asUTF8
    state = psStr
  elif obj.ofPyBytesObject:
    if state == psStr:
      return cannotMixPathLikeError()
    res = PyPathStr PyBytesObject(obj).asString
    state = psBytes
  else:
    return shouldBePathLike3Error(obj)
{.pop.}

converter toPyPathStr*(s: PyStr|PyBytes): PyPathStr = PyPathStr s
type PyPathStrTup = (PyPathStr, PyPathStr)  #tuple[a, b: PyPathStr]
converter toPyPathStr*[T: PyStr|PyBytes](s: (T, T)): PyPathStrTup = (PyPathStr s[0], PyPathStr s[1])
when PyPathStr is_not PyStr:
 proc toPy*(x: PyPathStrTup, res: var PyObject): PyBaseErrorObject =
  var pyt: array[2, PyObject]
  retIfExc toPy(x[0], pyt[0])
  retIfExc toPy(x[1], pyt[1])
  res = newPyTuple pyt


import ../private/utils
import ./utils

impObjects [
  pyobject,
  exceptions,
]

import ./purepath
export purepath
from ./purepathDecl import init

declarePyType PurePosixPath(base(PurePath)): discard
declarePyType PureWindowsPath(base(PurePath)): discard


template genInit*(os; sep) {.dirty.} =
  bind init
  proc `new os Path`*(args: openArray[PyObject]): PyObject =
    let res = `newPy os PathSimple`()
    retIfExc init(res, args, sep)
    res
  method getSep*(self: `Py os PathObject`): char {.raises: [].} = sep

genInit(PurePosix, '/')
genInit(PureWindows, '\\')

methodMacroTmpl(PurePath)

implPurePathMagic New:
  winOrPosix: newPyPureWindowsPathSimple()
  do: newPyPurePosixPathSimple()



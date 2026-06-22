
import ../private/utils
import ./utils

impObjects [
  pyobject,
  exceptions,
]


import ./path
export path

#XXX:PY-DIFF: multile inheritance is not supported
declarePyType WindowsPath(base(Path)): discard
declarePyType PosixPath(base(Path)): discard

genInit Posix, '/'
genInit Windows, '\\'

methodMacroTmpl(Path)


implPathMagic New:
  winOrPosix: newPyWindowsPathSimple()
  do: newPyPosixPathSimple()

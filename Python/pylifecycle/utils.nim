
import ../../Utils/[
  fileio,
]

import ../../Objects/[
  stringobject,
]
import ../coreconfig

proc Py_FdIsInteractive*(fp: fileio.File, filename: PyStrObject): bool =
  if isatty(fileno(fp)): 
    return true
  if not Py_GetConfig().interactive:
    return false
  return (filename.isNil or
        eqAscii(filename, "<stdin>") or
        eqAscii(filename, "???"))


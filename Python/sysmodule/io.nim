
when defined(nimPreviewSlimSystem):
  import std/assertions

import ../../Objects/[pyobjectBase, stringobject,]
import ../../Utils/compat
import ./attrs

proc PySys_EchoStderr*(s: string) =
  #TODO:sys.stderr
  assert:
    var unused: PyObject
    var exists: bool
    discard PySys_GetOptionalAttr(newPyAscii"stderr", unused, exists)
    not exists
  do: "sys.stderr shall be not set currently"

  errEchoCompatNoRaise s

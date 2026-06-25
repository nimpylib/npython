
import std/macros
import ./trans_pyimp
imp Python, getargs/dispatch
imp Python, getargs/dispatch/sym2def
impObjects [
  pyobject,
]
from pkg/pyio_abc import PathLike
impfspathUtils [decl]
export decl

genClinicGen os, [OSError]


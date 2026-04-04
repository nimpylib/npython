
import std/strformat
import ./versionInfo
export versionInfo

import ../Modules/getbuildinfo

proc Py_GetCompiler*: string =
  "[Nim " &  NimVersion & ']'

proc Py_GetVersion*: string =
  &"{Version:.80} ({Py_GetBuildInfo():.80}) {Py_GetCompiler():.80}"


template Py_PACK_FULL_VERSION(X, Y, Z, LEVEL, SERIAL): untyped = (
    ((X and 0xff) shl 24) or
    ((Y and 0xff) shl 16) or
    ((Z and 0xff) shl 8)  or 
    ((LEVEL and 0xf) shl 4) or
    ((SERIAL and 0xf) shl 0))

const PY_VERSION_HEX* =
  #[ Version as a single 4-byte hex number, e.g. 0x010502B2 == 1.5.2b2.
   Use this for numeric comparisons, e.g. #if PY_VERSION_HEX >= ... ]#
  Py_PACK_FULL_VERSION(
    PY_MAJOR,
    PY_MINOR,
    PyPatch,
    PY_RELEASE_LEVEL,
    PY_RELEASE_SERIAL)

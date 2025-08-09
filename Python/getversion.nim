
import std/strformat
import ./versionInfo
export versionInfo

import ../Modules/getbuildinfo

proc Py_GetCompiler*: string =
  "[Nim " &  NimVersion & ']'

proc Py_GetVersion*: string =
  &"{Version:.80} ({Py_GetBuildInfo():.80}) {Py_GetCompiler():.80}"


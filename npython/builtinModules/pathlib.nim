## a small shim for CPython/Lib/pathlib/

import std/macros
import ./private/utils
import ./private/gen
import pkg/handy_sugars/trans_imp

impObjects [
  pyobject,
  exceptions,
  moduleobjectImpl,
  stringobject,
]
impExpCwd pathlib, [
  purepaths, paths, meth,
]

const pathTypes = [
  "PurePath",
  "Path",
  "PurePosixPath",
  "PureWindowsPath",
  "PosixPath",
  "WindowsPath",
]

genModuleWithTypes pathlib, pathTypes


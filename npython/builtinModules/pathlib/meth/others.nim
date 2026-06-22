
include ./comm
import std/strutils

impObjects [
  bltcommon,
  exceptions,
  stringobject,

]

proc as_posix*(self: PyPurePathObject): string =
  self.str.replace(self.getSep(), '/')

implPurePathMethod as_posix(): newPyStr self.as_posix

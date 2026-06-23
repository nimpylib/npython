
include ./comm
impObjects [
  bltcommon,
  stringobject,
  exceptions,
  exceptions/oserr/convert,
]

import pkg/posixos/utils as os
import pkg/posixos/path

import ../path
methodMacroTmpl(Path)

template genClsMeth(cwd, impl) {.dirty.} =
  implPathMethod cwd(), [classmethod]:
    handleOsErrRetPyObj:
      PyTypeObject(selfNoCast).with_path impl

genClsMeth cwd, os.getcwd()
genClsMeth home:
  let homedir = expanduser("~")
  if homedir == "~":
    return newRuntimeError newPyAscii("could not determine home directory")
  homedir


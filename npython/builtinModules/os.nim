## equiv to Module/posixmodule.c
import pkg/handy_sugars/trans_imp
import pkg/posixos/consts as os_consts
import ./private/utils

impObjects [
  pyobject,
  exceptions,
  moduleobjectImpl,
  stringobject,
]
impExpCwd os, [
  decl, funcs,
]

const osModuleName* = "os"
proc PyInit_os*: PyObject =
  let os_name = os_consts.name
  result = PyModule_CreateInitialized(os)
  retIfExc result
  let modu = PyOsModuleObject result
  modu.dotname = newPyAscii os_name


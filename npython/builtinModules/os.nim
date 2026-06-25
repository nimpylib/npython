## equiv to Module/posixmodule.c
import pkg/handy_sugars/trans_imp
import pkg/posixos/consts as os_consts
import ./private/utils

impObjects [
  pyobject,
  exceptions,
  moduleobjectImpl,
  stringobject,
  dictobject,
]
impObjects pyobject_apis/attrs
imp Python, sysmodule_instance
impExpCwd os, [
  decl, funcs,
]
import ./path
export path

const osModuleName* = "os"
proc PyInit_os*: PyObject =
  let os_name = os_consts.name
  result = PyModule_CreateInitialized(os)
  retIfExc result
  let modu = PyOsModuleObject result
  modu.dotname = newPyAscii os_name

  # init os.path
  let obj = PyInit_path()
  retIfExc obj
  let pathMod = PyPathModuleObject obj
  modu.path = pathMod
  
  let moduS = newPyAscii"os.path"
  sys.modules[moduS] = pathMod

  # from os.path import ( ....
  for i in OsPathStrConsts:
    let asc = newPyAscii i
    let attr = PyObject_GetAttr(pathMod, asc)
    retIfExc attr
    retIfExc PyObject_SetAttr(modu, asc, attr)



import ../Objects/[
  pyobjectBase, dictobjectImpl, noneobject,
  exceptions, stringobject, moduleobject,
]
import ./sysmodule_instance
import ../Include/internal/[
  pycore_global_strings,
]


proc Py_GetMainModule*(): PyObject =
  ## `_Py_GetMainModule`
  result = sys.modules.getOptionalItem(pyDUId(main))
  if result.isNil:
    return pyNone

proc Py_CheckMainModule*(module: PyObject): PyBaseErrorObject =
  ## `_Py_CheckMainModule`
  if module.isNil or module.isPyNone:
    let name = pyDUId(main)
    let res = newModuleNotFoundError newPyStr "__main__ module not found"
    res.name = name
    return res
  if not module.pyType.isType pyModuleObjectType:
    let msg = "invalid __main__ module"
    let res = newImportError newPyStr msg
    res.name = pyDUId("__main__")
    return res

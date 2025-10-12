
import ../[
  sysmodule_instance,
]
import ../../Objects/[pyobject,
  exceptions,
  noneobject,
  stringobject,
  dictobject,
  moduleobject,
  boolobjectImpl,
]
import ../../Objects/pyobject_apis/attrs
import ../../Include/internal/pycore_global_strings
const HasImportLib = defined(npythonHasImportLib)  #TODO:imp
when HasImportLib:
  import ../../Objects/abstract/call
  import ../coreconfig

template import_add_moduleImpl(alreadyInAsgn): untyped{.dirty.} =
  var modu = sys.modules.getOptionalItem(name)
  if not modu.isNil and modu.ofPyModuleObject:
    alreadyInAsgn true
    return PyModuleObject modu
  alreadyInAsgn false
  modu = newPyModule(name)
  sys.modules[name] = modu
  PyModuleObject modu

proc import_add_module*(name: PyStrObject; alreadyIn: var bool): PyModuleObject =
  ## alreadIn is a `out` param
  template asgn(b) = alreadyIn = b
  import_add_moduleImpl asgn

proc import_add_module*(name: PyStrObject): PyModuleObject =
  ##[import.c:import_add_module

  Get the module object corresponding to a module name.
   First check the modules dictionary if there's one there,
   if not, create a new one and insert it in the modules dictionary.]##
  template dis(_) = discard
  import_add_moduleImpl dis

proc PyImport_AddModuleRef*(name: PyStrObject): PyObject = import_add_module name
proc PyImport_AddModuleRef*(name: string): PyObject =
  let name_obj = newPyStr name
  PyImport_AddModuleRef name_obj

using name: PyStrObject
proc import_get_module(name): PyObject = sys.modules.getOptionalItem name

proc PyModuleSpec_IsInitializing*(spec: PyObject; res: var bool): PyBaseErrorObject =
  ## Check if the "_initializing" attribute of the module spec is set to true.
  res = false
  if spec.isNil: return
  var value: PyObject
  var rc = PyObject_GetOptionalAttr(spec, pyId"_initializing", value)
  if rc == Error:
    return PyBaseErrorObject value
  PyObject_IsTrue(value, res)

proc import_ensure_initialized(modu: PyObject, name): PyBaseErrorObject =
  #[ Optimization: only call _bootstrap._lock_unlock_module() if
      __spec__._initializing is true.
      NOTE: because of this, initializing must be set *before*
      stuffing the new module in sys.modules.
  ]#
    #[ When -X importtime=2, print an import time entry even if an
       imported module has already been loaded.
     ]#
  
  proc done =
    when HasImportLib:
      if Py_GetConfig().import_time == 2:
        IMPORT_TIME_HEADER(interp)
        let import_level = FIND_AND_LOAD(interp).import_level
        let s = name.asUTF8.align(import_level * 2)
        errEchoCompat("import time: cached    | cached     | " & s)
  template goto_done =
    done()
    return
  var spec: PyObject
  var rc: bool
  let res = PyObject_GetOptionalAttr(modu, pyDUId(spec), spec)
  case res
  of Get:
    retIfExc PyModuleSpec_IsInitializing(spec, rc)
    if not rc: goto_done
  of Missing:
    goto_done
  else:
    return PyBaseErrorObject spec

  # Wait until module is done importing.
  when HasImportLib:
    retIfExc callMethod(
        IMPORTLIB(interp), pyId"_lock_unlock_module", name)

  goto_done


proc PyImport_GetModule*(name; res: var PyObject): PyBaseErrorObject =
  res = import_get_module(name)
  if res.isNil: return
  retIfExc res
  if res.isPyNone: return
  retIfExc import_ensure_initialized(res, name)

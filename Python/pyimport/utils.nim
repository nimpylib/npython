
import ../[
  sysmodule_instance,
]
import ../../Objects/[pyobject,
  stringobject,
  dictobject,
  moduleobject,
]

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

proc import_get_module*(name: PyStrObject): PyObject = sys.modules.getOptionalItem name

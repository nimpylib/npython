
import ./[initUtils,
  decl, initInfo,
]
#TODO
import ../coreconfig

import ../../Objects/[
  exceptions,
  dictobject,
  moduleobjectImpl,
]

import ../../Include/internal/pycore_initconfig

proc PySys_UpdateConfig*(sysmod: var PySysModuleObject, config: PyConfig): PyBaseErrorObject =
  ##[ `_PySys_UpdateConfig`

  Update sys attributes for a new PyConfig configuration.
This function also adds attributes that _PySys_InitCore() didn't add.
  ]##
  template COPY_FIELD_LIST(f, id) =
    sysmod.f = typeof(sysmod.f) !asList(config.id)
  template COPY_LIST(keyId, valueF) =
    when compiles(sysmod.keyId):
      COPY_FIELD_LIST(keyId, valueF)
    else:
      SET_SYS(astToStr(key), asList(config.valueF))
  template COPY_LIST(id) = COPY_LIST(id, id)

  #template COPY_FIELD_LIST(id) = COPY_FIELD_LIST(id, id)
  #COPY_WSTR
  let sysdict = sysmod.getDict

  #template COPY_STR(attr, s) = SET_SYS(KEY, newPyStr(s))
  template COPY_STR(id) = SET_SYS(astToStr(id), config.id)

  COPY_LIST path, module_search_paths

  COPY_STR executable
  
  COPY_LIST argv
  COPY_LIST orig_argv

template PyImport_InitModules(): PyDictObject = newPyDict()  #TODO:import_mod
proc PySys_Create*(sysmod: var PySysModuleObject): PyBaseErrorObject =
  ##[`_PySys_Create`  called by pylifecycle:pycore_interp_init

  Create sys module without all attributes.
   PySys_UpdateConfig() should be called later to add remaining attributes.]##
  let modules = PyImport_InitModules()
  let sysmodE = PyModule_CreateInitialized(sys)
  retIfExc sysmodE
  sysmod = PySysModuleObject sysmodE

  let sysdict = sysmod.getDict()

  #TODO:io

  retIfExc initCore(sysdict)

  sysmod.modules = modules

  #TODO:monioring


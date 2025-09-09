
import std/strformat
import std/macros
import ../Objects/[
  pyobject,
  stringobject,
  dictobject,
  tupleobject,
  exceptions,
  moduleobjectImpl,
]
import ../Include/modsupport
import ../Utils/trans_imp
impExp sysmodule,
  decl, initInfo, audit


methodMacroTmpl(SysModule)

implSysModuleMethod audit(eventObj: PyStrObject, *args):
  let (event, event_length) = eventObj.asUTF8AndSize()
  if event.len != event_length:
    return newValueError newPyAscii"embeded null character"
  auditTuple(cstring event, newPyTuple args)


template PyImport_InitModules(): PyDictObject = newPyDict()  #TODO:import_mod
proc PySys_Create*(sysmod: var PySysModuleObject): PyBaseErrorObject =
  ##[`_PySys_Create`  called by pylifecycle:pycore_interp_init

  Create sys module without all attributes.
   PySys_UpdateConfig() should be called later to add remaining attributes.]##
  let modules = PyImport_InitModules()
  let sysmodE = PyModule_CreateInitialized(SysModule,
    newPyModuleDef("sys", pySysModuleObjectType),
    NPYTHON_API_VERSION
  )
  retIfExc sysmodE
  sysmod = PySysModuleObject sysmodE

  let sysdict = sysmod.getDict()

  #TODO:io

  retIfExc initCore(sysdict)

  sysmod.modules = modules

  #TODO:monioring

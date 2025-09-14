
import std/strformat
import std/macros
import ../Objects/[
  pyobject,
  stringobject,
  tupleobject,
  exceptions,
  noneobject,
  typeobject,
]
import ../Objects/bltcommon; export bltcommon
import ../Utils/trans_imp
impExp sysmodule,
  decl, init, audit, hooks, attrs


methodMacroTmpl(SysModule)

implSysModuleMethod audit(eventObj: PyStrObject, *args):
  let (event, event_length) = eventObj.asUTF8AndSize()
  if event.len != event_length:
    return newValueError newPyAscii"embeded null character"
  auditTuple(cstring event, newPyTuple args)

implSysModuleMethod excepthook(exctype: PyTypeObject, value: PyBaseErrorObject, traceback):
  excepthook(exctype, value, traceback)
  pyNone

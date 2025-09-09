
import std/strformat
import std/macros
import ../Objects/[
  pyobject,
  stringobject,
  tupleobject,
  exceptions,
]
import ../Utils/trans_imp
impExp sysmodule,
  decl, init, audit


methodMacroTmpl(SysModule)

implSysModuleMethod audit(eventObj: PyStrObject, *args):
  let (event, event_length) = eventObj.asUTF8AndSize()
  if event.len != event_length:
    return newValueError newPyAscii"embeded null character"
  auditTuple(cstring event, newPyTuple args)


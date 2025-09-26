
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
import ../Objects/numobjects/intobject_decl
import ../Objects/bltcommon; export bltcommon
import ../Utils/trans_imp
import ./getargs/va_and_kw
impExp sysmodule,
  decl, init, audit, hooks, attrs, int_max_str_digits


methodMacroTmpl(SysModule)

implSysModuleMethod audit(eventObj: PyStrObject, *args):
  let (event, event_length) = eventObj.asUTF8AndSize()
  if event.len != event_length:
    return newValueError newPyAscii"embeded null character"
  auditTuple(cstring event, newPyTuple args)

implSysModuleMethod excepthook(exctype: PyTypeObject, value: PyBaseErrorObject, traceback):
  excepthook(exctype, value, traceback)
  pyNone

implSysModuleMethod get_int_max_str_digits(): newPyInt PySys_GetIntMaxStrDigits()
implSysModuleMethod set_int_max_str_digits(*a, **kw):
  retIfExc PyArg_ParseTupleAndKeywordsAs("set_int_max_str_digits", a, kw, [], maxdigits: int)
  retIfExc PySys_SetIntMaxStrDigits(maxdigits)
  pyNone

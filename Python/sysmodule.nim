
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
  
import ../Objects/exceptions/extra_utils
import ../Objects/numobjects/[intobject_decl, numobjects_comm]
import ../Objects/bltcommon; export bltcommon
import ../Utils/trans_imp
from ./neval_frame import privateGetframeNoAudit
import ./getargs/[vargs, va_and_kw, dispatch]
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
implSysModuleMethod displayhook(x): displayhook(x)

implSysModuleMethod get_int_max_str_digits(): newPyInt PySys_GetIntMaxStrDigits()
implSysModuleMethod set_int_max_str_digits(maxdigits: int):
  retIfExc PySys_SetIntMaxStrDigits(maxdigits)
  pyNone

proc exit*(status: PyObject = pyNone): PyObject{.clinicGenWithPrefix"sys".} =
  ## sys.exit([status])
  let res = PyErr_CreateException(pySystemExitObjectType, status)
  res.thrown = true
  return res

implSysModuleMethod "_getframe"(depth = 0):
  result = privateGetframeNoAudit(depth)
  retIfExc audit("sys._getframe", result)

implSysModuleMethod exit(exitcode = PyObject pyIntZero): sysmodule.exit(exitcode)

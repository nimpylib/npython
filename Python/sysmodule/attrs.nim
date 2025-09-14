

import ../sysmodule_instance
import ../../Objects/[
  pyobject,
  stringobject, exceptions,
  moduleobject, dictobject,
]
template sysdict: PyDictObject = sys.getDict()
export sysdict

template opOr(sysd: PyDictObject, op; elseDo) =
  if sysd.isNil: elseDo
  else:
    op

proc PySys_GetOptionalAttr*(name: PyStrObject, value: var PyObject, exists: var bool): PyBaseErrorObject =
  sysdict.opOr:
    exists = sysdict.getItemRef(name, value)
  do: value=nil
proc PySys_GetOptionalAttr*(name: PyStrObject, value: var PyObject): PyBaseErrorObject =
  var unused: bool
  PySys_GetOptionalAttr(name, value, unused)

proc no_sys_module: PyBaseErrorObject = newRuntimeError(newPyAscii"no sys module")
proc PySys_GetAttr*(name: PyStrObject, value: var PyObject): PyBaseErrorObject =
  sysdict.opOr:
    var exists = sysdict.getItemRef(name, value)
    if not exists:
      return newRuntimeError(newPyAscii"lost sys." & name)
  do: return no_sys_module()
proc PySys_GetAttr*(name: PyStrObject): PyObject =
  let exc = PySys_GetAttr(name, result)
  retIfExc exc

proc PySys_SetAttrNonNil*(name: PyStrObject, valueNonNil: PyObject): PyBaseErrorObject =
  sysdict.opOr:
    return sysdict.setItem(name, valueNonNil)
  do: return no_sys_module()


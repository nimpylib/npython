

import ../sysmodule_instance
import ../../Objects/[
  pyobject,
  stringobject, exceptions,
  moduleobject, dictobject,
]
template sysdict: PyDictObject = sys.getDict()
export sysdict

template opOr(sysd: PyObject, op; elseDo) =
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

proc lost_sys_attr(name: PyStrObject): PyBaseErrorObject =
  newRuntimeError(newPyAscii"lost sys." & name)
template getImpl(result, sysdict, name, get) =
  bind opOr, lost_sys_attr, no_sys_module
  opOr sysdict:
    let exists = get
    if not exists:
      result = lost_sys_attr name
  do: result = no_sys_module()
proc PySys_GetAttr*(name: PyStrObject, value: var PyObject): PyBaseErrorObject =
  getImpl result, sysdict, name,
    sysdict.getItemRef(name, value)
template PySys_GetDataChecked*(attr: untyped): PyObject =
  ## XXX:FIXME: currently only this can be used for data property of sys,
  ##   e.g. stdout, stderr
  ##
  ## If using PySys_GetAttr, PySys_GetOptionalAttr, PySys_GetObject,
  ## always get nothing.
  bind getImpl, sys
  var res: PyObject
  getImpl res, sys, pyId astToStr(attr):
    res = sys.attr
    not res.isNil
  res

proc PySys_GetAttr*(name: PyStrObject): PyObject =
  let exc = PySys_GetAttr(name, result)
  retIfExc exc

proc PySys_SetAttrNonNil*(name: PyStrObject, valueNonNil: PyObject): PyBaseErrorObject =
  sysdict.opOr:
    return sysdict.setItem(name, valueNonNil)
  do: return no_sys_module()

proc PySys_GetObject*(name: cstring): PyObject =
  let nameObj = newPyStr(name)
  discard PySys_GetOptionalAttr(nameObj, result)


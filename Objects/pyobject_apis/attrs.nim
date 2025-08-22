
import ../[
  pyobject,
  stringobject,
  exceptions,
]
import ../../Utils/optres
import ./[
  attrsUtils, attrsGeneric
]

export attrsGeneric
export asAttrNameOrRetE
export GetItemRes

proc PyObject_GetAttr*(v: PyObject, name: PyStrObject|PyObject): PyObject =
  nameAsStr
  let fun = v.getMagic(getattr)
  assert not fun.isNil
  #XXX:type npython requires all pyType is `ready`
  # if fun.isNil: return newAttributeError(v, name)
  fun(v, name)

proc PyObject_GetOptionalAttr*(v: PyObject, name: PyStrObject|PyObject, res: var PyObject): GetItemRes =
  ## - on AttributeError, res will be nil, result will be `Missing`
  ## - on other exceptions, res will be that exception, result will be `Error`
  nameAsStr
  #TODO:tp_getattr,tp_getattro
  let tp = v.pyType
  let tp_getattro = tp.magicMethods.getattr
  if tp_getattro == PyObject_GenericGetAttr:
    res = PyObject_GenericGetAttrWithDict(v, name, nil, true)
    if not res.isNil: return GetItemRes.Get
    if res.isThrownException: return GetItemRes.Error
    return GetItemRes.Missing
  #[ #TODO:Py_type_getattro
  when declared(Py_type_getattro):
    if tp_getattro == Py_type_getattro:
  ]#
  let fun = tp.magicMethods.getattr
  if not fun.isNil:
    res = fun(v, name)
  else:
    res = nil
    return GetItemRes.Missing
  if res.isThrownException:
    if res.isExceptionOf Attribute:
      res = nil
      return GetItemRes.Missing
    return GetItemRes.Error
  return GetItemRes.Get

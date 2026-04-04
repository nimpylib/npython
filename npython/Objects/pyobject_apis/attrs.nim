
import std/strformat
import ../[
  pyobject,
  noneobject,
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
  when name is_not PyStrObject:
    result = GetItemRes.Error
    let name = name.asAttrNameOrSetExc res
  #TODO:tp_getattr,tp_getattro
  let tp = v.pyType
  let tp_getattro = tp.magicMethods.getattr
  if tp_getattro == PyObject_GenericGetAttr:
    res = PyObject_GenericGetAttrWithDict(v, name, nil, true)
    if res.isNil: return GetItemRes.Missing
    elif res.isThrownException: return GetItemRes.Error
    else: return GetItemRes.Get
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

proc PyObject_HasAttrWithError*(obj: PyObject, name: PyStrObject|PyObject, exc: var PyBaseErrorObject): GetItemRes =
  var res: PyObject
  result = PyObject_GetOptionalAttr(obj, name, res)
  if result == Error:
    exc = PyBaseErrorObject res

#TODO:hasattr proc PyObject_HasAttr*(obj: PyObject, name: PyStrObject|PyObject): bool =

proc PyObject_SetAttr*(self: PyObject, name: PyStrObject|PyObject, value: PyObject): PyObject {. pyCFuncPragma .} =
  nameAsStr
  let fun = self.getMagic(setattr)
  if fun.isNil:
    let pre = if value.isNil: "del" else: "assign to"
    return newTypeError newPyStr(
      fmt"{self.typeName:.100s} object has no attributes ({pre} .{$name})"
    )
  retIfExc fun(self, name, value)
  pyNone

proc PyObject_DelAttr*(self: PyObject, name: PyStrObject|PyObject): PyObject {. pyCFuncPragma .} = PyObject_SetAttr(self, name, nil)

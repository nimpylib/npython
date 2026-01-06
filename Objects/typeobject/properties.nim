
import std/strformat
import ../../Include/internal/pycore_global_strings
import ../[
  pyobject,
  dictobject,
  stringobject,
  exceptions,
]
import ./[decl, getters]

import ../../Python/sysmodule/audit
methodMacroTmpl(Type)


proc get_module(tp: PyTypeObject): PyObject{.inline.} =
  ## type_get_module
  type_module(tp)


proc check_set_special_type_attr(typ: PyTypeObject, value: PyObject, name: string): PyBaseErrorObject =
  if value.isNil:
    return newTypeError(
      newPyStr &"cannot delete '{name}' attribute of type '{typ.name}'"
    )
  if hasFeature(typ, Py_TPFLAGS.IMMUTABLETYPE):
    return newTypeError(
      newPyStr &"cannot set '{name}' attribute of immutable type '{typ.name}'"
    )

  retIfExc audit("object.__setattr__", typ, name, value)

proc set_module(typ: PyTypeObject, value: PyObject): PyBaseErrorObject =
  ## type_set_module
  retIfExc check_set_special_type_attr(typ, value, "__module__")

  #TODO:type
  #TODO:mro
  #PyType_Modified(typ)

  let dict = PyDictObject typ.getDictUnsafe
  var res: PyObject
  discard dict.pop(pyDUId(firstlineno), res)
  assert res.isNil or not res.isThrownException
  
  dict.setItem(pyDUId(module), value)

genProperty Type, "__module__", module, self.get_module: self.set_module other

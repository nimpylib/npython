
import ../Include/internal/pycore_global_strings
import ./[
  pyobject,
  stringobject,
  noneobject,
  dictobject,
]

declarePyType Module(dict):
  name{.dunder_member.}: PyStrObject  ## `->md_def->md_name`
  # optional
  #package{.dunder_member.}: PyObject
  #spec{.dunder_member.}: PyObject

using self: PyModuleObject
proc getDict*(self): PyDictObject =
  ## _PyModule_GetDict(mod) must not be used after calling module_clear(mod)
  result = PyDictObject self.dict
  assert not result.isNil

proc init_dict(modu: PyModuleObject, md_dict: PyDictObject, name: PyStrObject) =
  md_dict[pyDUId package] = pyNone
  md_dict[pyDUId loader] = pyNone
  md_dict[pyDUId spec] = pyNone


proc initFrom_PyModule_NewObject(module: PyModuleObject) =
  ## like `PyModule_NewObject` but is a `init`
  module.dict = newPyDict()
  module.init_dict(module.getDict, module.name)

template newPyModuleImpl*(T: typedesc[PyModuleObject]; typ: PyTypeObject; nam: PyStrObject|string;
    tp_alloc_may_exc = true
  ){.dirty.} =
  ## for subtype
  bind newPyStr, initFrom_PyModule_NewObject
  block:
    let resObj = typ.tp_alloc(typ, 0)
    when tp_alloc_may_exc:
      static:assert result is_not PyModuleObject,
        "tp_alloc_may_exc is true but we cannot return exception for type " &
          $typeof(result)
      retIfExc resObj
    let res = T resObj
    res.pyType = typ
    res.name = newPyStr(nam)
    initFrom_PyModule_NewObject(res)
    result = res

proc newPyModule*(name: PyStrObject|string): PyModuleObject =
  newPyModuleImpl PyModuleObject, pyModuleObjectType, name, false

type PyModuleDef* = object
  m_name*: string
  typ*: PyTypeObject

proc newPyModuleDef*(name: string, typ: PyTypeObject): PyModuleDef =
  PyModuleDef(
    m_name: name,
    typ: typ,
  )

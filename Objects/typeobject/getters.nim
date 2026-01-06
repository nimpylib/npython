
import ../[
  pyobjectBase, stringobject, exceptions,
]
import ../dictobject/ops
import ../stringobject/utf8apis
import ../../Include/internal/pycore_global_strings
import ../stringobject/internal

using typ: PyTypeObject

proc hasFeature*(typ: PyTypeObject, flag: PY_TPFLAGS): bool =
  ## type_has_feature
  (typ.tp_flags & flag)

proc addFlags*(typ: PyTypeObject, flags: PY_TPFLAGS) =
  ## type_add_flags
  typ.tp_flags = typ.tp_flags or flags

proc type_qualname(typ): PyObject =
  #TODO:tp_flags
  newPyStr typ.name
proc type_module*(typ): PyObject =
  ## unstable
  var modu: PyObject
  if typ.hasFeature(Py_TPFLAGS.HEAPTYPE):
    let dict = PyDictObject typ.getDictUnsafe
    let id = pyDUId module
    if not dict.getItemRef(id, modu):
      return newAttributeError id
  else:
    let s = typ.name.find '.'
    if s >= 0:
      modu = PyUnicode_fromStringAndSize(typ.name, s)
      if not modu.isThrownException:
        PyUnicode_InternMortal(PyStrObject modu)
    else:
      modu = pyId builtins
  return modu


proc getQualName*(typ): PyObject =
  ## `PyType_GetQualName`
  type_qualname(typ)

proc getFullyQualifiedName*(typ; sep: char): PyObject =
  ## `_PyType_GetFullyQualifiedName`
  if not typ.hasFeature(Py_TPFLAGS.HEAPTYPE):
    return newPyStr typ.name
  let qualname = type_qualname(typ)
  retIfExc qualname
  let squal = PyStrObject qualname
  let module = type_module(typ)
  retIfExc module
  var smod: PyStrObject
  if module.ofPyStrObject and (smod = PyStrObject module; smod) != pyId builtins and
      smod != pyDUId main:
    result = smod & sep & squal
  else:
    result = qualname

proc getFullyQualifiedName*(typ): PyObject =
  ## PyType_GetFullyQualifiedName
  typ.getFullyQualifiedName '.'


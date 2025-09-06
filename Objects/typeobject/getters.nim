
import ../[
  pyobjectBase, stringobject, exceptions,
]
import ../stringobject/utf8apis
import ../../Include/internal/pycore_global_strings
import ../stringobject/internal

using typ: PyTypeObject
proc type_qualname(typ): PyObject =
  #TODO:tp_flags
  newPyStr typ.typeName
proc type_module(typ): PyObject =
  #TODO:tp_flags
  let idx = typ.name.find('.')
  if idx >= 0:
    let modu = PyUnicode_fromStringAndSize(typ.name, idx)
    retIfExc modu
    let m = PyStrObject modu
    PyUnicode_InternMortal(m)
    m
  else:
    pyId builtins


proc getFullyQualifiedName*(typ; sep: char): PyObject =
  ## `_PyType_GetFullyQualifiedName`
  #TODO:tp_flags
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


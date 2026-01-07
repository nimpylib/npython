
import std/macros
import ../[
  stringobject,
]
include ./common_h
import ./basetok
export stringobject

template addTp*(tp; basetype) = 
  tp.kind = PyTypeToken.BaseException
  tp.base = basetype
template addTpOfBaseWithName*(name) = 
  addTp `py name ObjectType`, pyBaseErrorObjectType

template newProcTmpl*(excpName; tok: ExceptionToken|BaseExceptionToken){.dirty.} = 
  # use template for lazy evaluation to use PyString
  # theses two templates are used internally to generate errors (default thrown)
  bind PyStrObject, newPyTuple
  proc `new excpName Impl`: `Py excpName Object` = 
    let excp = `newPy excpName Simple`()
    when tok is ExceptionToken:
      excp.tk = tok
    else:
      excp.base_tk = tok
    excp.thrown = true
    excp
  proc `new excpName`*: `Py excpName Object`{.inline.} = 
    let excp = `new excpName Impl`()
    excp.args = newPyTuple()
    excp
  proc `new excpName`*(msgStr: PyStrObject): `Py excpName Object`{.inline.} = 
    let excp = `new excpName Impl`()
    excp.args = newPyTuple [PyObject msgStr]
    excp


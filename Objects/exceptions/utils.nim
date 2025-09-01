
import std/macros
import ../[
  noneobject, stringobject, tupleobject,
]
import ./basetok
export stringobject

template addTp*(tp; basetype) = 
  tp.kind = PyTypeToken.BaseError
  tp.base = basetype
template addTpOfBaseWithName*(name) = 
  addTp `py name ErrorObjectType`, pyBaseErrorObjectType

macro setAttrsNone*(tok: static[ExceptionToken], self) =
  result = newStmtList()
  for n in extraAttrs(tok):
    result.add newAssignment(
      newDotExpr(self, n),
      bindSym"pyNone"
    )

template newProcTmpl*(excpName, tok){.dirty.} = 
  # use template for lazy evaluation to use PyString
  # theses two templates are used internally to generate errors (default thrown)
  bind PyStrObject, newPyTuple
  proc `new excpName Error`*: `Py excpName ErrorObject`{.inline.} = 
    let excp = `newPy excpName ErrorSimple`()
    excp.tk = ExceptionToken.`tok`
    excp.thrown = true
    setAttrsNone ExceptionToken.tok, excp
    excp

  proc `new excpName Error`*(msgStr: PyStrObject): `Py excpName ErrorObject`{.inline.} = 
    let excp = `new excpName Error`()
    excp.args = newPyTuple [PyObject msgStr]
    excp

template newProcTmpl*(excpName) = 
  newProcTmpl(excpName, excpName)

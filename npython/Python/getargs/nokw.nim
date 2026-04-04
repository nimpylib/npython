
import ../../Objects/[
  stringobject, exceptions/base
]

template PyArg_NoKw*(funcname; kw){.dirty.} =
  ## this is not `_PyArg_NoKeywords`, as it doesn't check if kw.len == 0 !
  ## only used for BltinMethod/BltinFunc, not for Python's function check
  ## 
  ## And unlike `PyArg_NoKwname`, kw shall be PyDictObject
  bind newTypeError, newPyStr, `&`
  #TODO:rec-dep shall also check `or kw.len > 0`
  if not kw.isNil: return newTypeError newPyStr(funcname)&newPyStr"() takes no keyword arguments"

template PyArg_NoKw*(funcname){.dirty.} =
  bind PyArg_NoKw
  PyArg_NoKw funcname, kwargs

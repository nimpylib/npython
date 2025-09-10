import ../Objects/dictobject

let bltinDict* = newPyDict()  ## inner

proc PyEval_GetBuiltins*: PyDictObject =
  ## `ceval:_PyEval_GetBuiltins`
  ##
  ## returns builtins dict
  bltinDict

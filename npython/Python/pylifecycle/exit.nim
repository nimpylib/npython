
import std/macros

import ../../Objects/[
  dictobject,
]
import ../[
  coreconfig,
  sysmodule_instance,
  builtindict,
]

import ../../Utils/[compat, nexportc]

var finalized: bool

proc Py_Finalize*(): bool{.discardable, npyexportc.} =
  #TODO:Py_Finalize
  result = true
  if finalized:
    return
  finalized = true
  template clear[T](s: T) = s = default T
  macro clearEachSeq(s: varargs[untyped]) =
    result = newStmtList()
    for i in s:
      result.add quote do:
        `i`.clear()
  clearEachSeq(
    pyConfig,
    sys,
    bltinDict,
  )


proc Py_Exit*(sts: int) {.noReturn.}=
  var sts = sts
  if not Py_Finalize():
    sts = 120
  quitCompat sts

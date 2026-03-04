
import ./decl
import pkg/intobject/frexp

proc frexp*(a: PyIntObject, e: var int64): float =
  ## `_PyLong_Frexp`
  a.v.frexp(e)

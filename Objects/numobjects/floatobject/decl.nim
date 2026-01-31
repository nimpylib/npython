
when defined(nimPreviewSlimSystem):
  import std/formatfloat
  export formatfloat

import ../../pyobject
declarePyType Float(tpToken):
  v: float

method `$`*(f: PyFloatObject): string{.raises: [].} = 
  $f.v


proc newPyFloat*(v: float): PyFloatObject =
  ## `PyFloat_FromDouble`
  result = newPyFloatSimple()
  result.v = v

proc newPyFloat*(v: PyFloatObject): PyFloatObject = v

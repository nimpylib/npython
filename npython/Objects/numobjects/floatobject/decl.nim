
import pkg/nimpatch/floatdollar

import ../../pyobject
declarePyType Float(tpToken, typeName("float")):
  v: float

method `$`*(f: PyFloatObject): string{.raises: [].} = 
  floatdollar.`$` f.v


proc newPyFloat*(v: float): PyFloatObject =
  ## `PyFloat_FromDouble`
  result = newPyFloatSimple()
  result.v = v

proc newPyFloat*(v: PyFloatObject): PyFloatObject = v

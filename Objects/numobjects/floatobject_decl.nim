

import ../pyobject
declarePyType Float(tpToken):
  v: float

method `$`*(f: PyFloatObject): string{.raises: [].} = 
  $f.v


proc newPyFloat*(v: float): PyFloatObject = 
  result = newPyFloatSimple()
  result.v = v

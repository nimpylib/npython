import pyobject

declarePyType Bool(tpToken):
  b: bool

proc newPyBoolInner(b: bool): PyBoolObject = 
  result = newPyBoolSimple()
  result.b = b


let pyTrueObj* = newPyBoolInner(true)  ## singleton
let pyFalseObj* = newPyBoolInner(false)  ## singleton

proc newPyBool*(b: bool): PyBoolObject =
  if b: pyTrueObj
  else: pyFalseObj
